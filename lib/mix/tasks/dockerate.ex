defmodule Mix.Tasks.Dockerate do
  use Mix.Task

  @default_base_image "elixir:latest"
  @ssh_agent_image "nardeas/ssh-agent:latest"
  @default_source_dirs ["config", "lib", "rel", "priv", "web"]

  @shortdoc "Assemble a Docker image"


  def run(args) do
    # Determine app name
    app = Mix.Project.config |> Keyword.get(:app)
    version = Mix.Project.config |> Keyword.get(:version)
    info "Assembling a Docker image for app #{app} #{version}, env = #{Mix.env}..."

    # Determine release name 
    # FIXME read this from rel/config.exs
    rel_name = app


    # Determine base image
    {base_image_build, base_image_release} = 
      case Mix.Project.config |> Keyword.get(:dockerator_base_image) do
        nil ->
          {@default_base_image, @default_base_image}

        image when is_binary(image) ->
          {image, image}

        image when is_list(image) ->
          {Keyword.get(image, :build, @default_base_image), Keyword.get(image, :release, @default_base_image)}

        other ->
          error "Invalid base image #{inspect(other)}"
          Kernel.exit(:invalid_base_image)
      end
    info "Using #{base_image_build} as a base Docker image for build phase"
    info "Using #{base_image_release} as a base Docker image for release phase"


    # Determine source directories
    source_dirs = 
      case Mix.Project.config |> Keyword.get(:dockerator_source_dirs) do
        nil ->
          @default_source_dirs

        other when is_list(other) ->
          other

        other ->
          error "Invalid source dirs #{inspect(other)}"
          Kernel.exit(:invalid_source_dirs)
      end
    info "Using #{inspect(source_dirs)} as a list of source directories"


    # Determine target tag
    target_tag = case args do
      ["release"] ->
        version

      [] ->
        "latest"

      other ->
        error "Invalid argument #{inspect(other)}, please pass \"release\" or leave it blank"
        Kernel.exit(:invalid_argument)
    end


    # Determine target image
    target_image = 
      case Mix.Project.config |> Keyword.get(:dockerator_target_image) do
        nil ->
          error "Target image is unset, please set :dockerator_target_image in the app's config in mix.exs"
          Kernel.exit(:unset_target_image)

        image when is_binary(image) ->
          image

        other ->
          error "Invalid target image #{inspect(other)}"
          Kernel.exit(:invalid_target_image)
      end
    target_image_build = "#{target_image}/build:#{target_tag}"
    target_image_release = "#{target_image}:#{target_tag}"

    info "Using #{target_image_release} as a target Docker image"


    # Determine extra release commands
    release_extra_docker_commands = 
      case Mix.Project.config |> Keyword.get(:dockerator_release_extra_docker_commands) do
        nil ->
          []

        other when is_list(other) ->
          info "Using #{inspect(other)} as a list of extra commands for the release Docker image"
          other

        other ->
          error "Invalid extra release commands #{inspect(other)}"
          Kernel.exit(:invalid_release_extra_docker_commands)
      end


    # Determine templates' path
    templates_path = 
      Mix.Project.deps_paths[:dockerator]
      |> Path.join("priv")
      |> Path.join("templates")


    # Determine build path
    build_path = 
      Mix.Project.build_path
      |> Path.join("dockerator")

    build_output_path = 
      build_path
      |> Path.join("output")

    build_output_path_relative =
      build_output_path 
      |> Path.relative_to_cwd

    build_scripts_path = 
      build_path
      |> Path.join("scripts")


    # Create directory for build files
    with \
      :ok <- File.mkdir_p(build_path), 
      {:ok, _} <- File.rm_rf(build_output_path), 
      :ok <- File.mkdir_p(build_output_path), 
      :ok <- File.mkdir_p(build_scripts_path)
    do 
      info "Using #{build_path} as a temporary build path"

    else
      e ->
        error "Failed to create build directory #{build_path}: #{inspect(e)}"
        Kernel.exit(:failed_build_directory)
    end

    # Check if we're using any git dependencies
    git_deps_urls = 
      Mix.Dep.Lock.read 
      |> Map.values
      |> Enum.filter(fn
        {:git, _git_url, _, _} -> true
        _ -> false
      end)
      |> Enum.map(fn({_, dep_url, _, _}) ->
        case URI.parse(dep_url) do
          %URI{scheme: nil} ->
            "ssh://#{dep_url}"
          
          other ->
            other
        end
      end)
      |> Enum.uniq

    case git_deps_urls do
      [] ->
        info "Found no git dependencies"

      other ->
        info "Found the following git dependencies:"

        Enum.each(other, fn(git_dep_url) ->
          info "  #{git_dep_url}"
        end)
    end


    # Generate scripts from templates
    dockerfile_build = 
      Path.join(templates_path, "build.Dockerfile.eex")
      |> EEx.eval_file([base_image: base_image_build, mix_env: Mix.env, git_deps_urls: git_deps_urls, source_dirs: source_dirs])

    dockerfile_release = 
      Path.join(templates_path, "release.Dockerfile.eex")
      |> EEx.eval_file([base_image: base_image_release, mix_env: Mix.env, build_output_path_relative: build_output_path_relative, release_extra_docker_commands: release_extra_docker_commands, rel_name: rel_name])

    # Remove empty lines in Dockerfile as they're deprecated
    dockerfile_build = Regex.replace(~r/\n+/, dockerfile_build, "\n")
    dockerfile_release = Regex.replace(~r/\n+/, dockerfile_release, "\n")

    dockerfile_build_path = 
      build_scripts_path
      |> Path.join("build.Dockerfile")

    dockerfile_release_path = 
      build_scripts_path
      |> Path.join("release.Dockerfile")

    with \
      :ok <- File.write(dockerfile_build_path, dockerfile_build),
      :ok <- File.write(dockerfile_release_path, dockerfile_release)
    do
      info "Succesfully generated build scripts"

    else
      e ->
        error "Failed to generate build scripts: #{inspect(e)}"
        Kernel.exit(:failed_build_scripts)
    end


    # Check if we need a SSH agent
    ssh_agent = 
      case Mix.Project.config |> Keyword.get(:dockerator_ssh_agent) do
        nil ->
          false

        other when is_boolean(other) ->
          other
        
        other ->
          error "Invalid SSH agent setting #{inspect(other)}"
          Kernel.exit(:invalid_ssh_agent)
      end

    ssh_agent_docker_name =
      String.replace(target_image, "/", "_") <> "-sshagent"

    if ssh_agent do      
      case System.cmd "docker", ["inspect", "-f", "'{{.State.Running}}'", ssh_agent_docker_name] do
        {"'true'\n", 0} ->
          info "SSH agent seems to be already running"
          info "  If you want to clean it, kill it by invoking the following command:"
          info "  docker rm #{ssh_agent_docker_name} -f"

        {"'false'\n", 0} ->
          info "SSH agent seems to be present but not running, starting"
          case docker_cmd_passthrough ["start", ssh_agent_docker_name] do
            :ok ->
              ssh_agent_add_keys!(ssh_agent_docker_name)

            {:error, code} ->
              error "Docker run returned error code #{code}"
              Kernel.exit(:failed_docker_start_ssh_agent)
          end

        {"\n", 1} ->
          info "Starting SSH agent (#{ssh_agent_docker_name})"
          case docker_cmd_passthrough ["run", "-d", "--name=#{ssh_agent_docker_name}", @ssh_agent_image] do
            :ok ->
              ssh_agent_add_keys!(ssh_agent_docker_name)

          {:error, code} ->
            error "Docker run returned error code #{code}"
            Kernel.exit(:failed_docker_run_ssh_agent)
        end
      end
    end


    # Phase 1: Prepare build image
    info "Building image for the build phase (#{target_image_build})"
    case docker_cmd_passthrough ["build", "-t", target_image_build, "-f", dockerfile_build_path, "."] do
      :ok ->
        info "Built image for the build phase"

      {:error, code} ->
        error "Docker build returned error code #{code}"
        Kernel.exit(:failed_docker_build)
    end
    

    # Phase 2: Prepare release
    info "Building release"

    release_docker_extra_args = if ssh_agent do
      ["--volumes-from=#{ssh_agent_docker_name}", "-e", "SSH_AUTH_SOCK=/.ssh-agent/socket"]   
    else
      []
    end

    release_docker_args = ["run"] ++ 
      release_docker_extra_args ++ 
      [
        "--mount", "type=bind,source=#{build_output_path},target=/root/output", 
        "--rm", 
        "-t", target_image_build, 
        "sh", "-c", "(mix deps.get && mix compile && mix release && mv -v _build/#{Mix.env}/rel/#{rel_name} /root/output/app/)"
      ]

    case docker_cmd_passthrough release_docker_args do
      :ok ->
        info "Built release"

      {:error, code} ->
        error "Release returned error code #{code}"
        Kernel.exit(:failed_release)
    end


    # Phase 3: Prepare release image
    info "Building image for the release phase (#{target_image_release})"
    case docker_cmd_passthrough ["build", "-t", target_image_release, "-f", dockerfile_release_path, "."] do
      :ok ->
        info "Built image for the release phase"

      {:error, code} ->
        error "Docker build returned error code #{code}"
        Kernel.exit(:failed_docker_build)
    end
    

    info "Done. Your app is bundled in the image #{target_image_release}."
  end


  defp ssh_agent_add_keys!(ssh_agent_docker_name) do
    case :os.type do
      {:unix, :darwin} ->
        info "Adding your SSH keys to the SSH agent."
        info "  Please type password for your SSH keys in the new Terminal window if they're password-protected."

        # This hack is necessary because it is very hard to call 
        # PTY-enabled command from Elixir/Erlang, so we just spawn new 
        # Terminal window in case of users' SSH keys are 
        # password-protected.
        #
        # The last line kills the terminal window so we don't wait for
        # Command+Q.       
        tmp_script_path = "/tmp/#{ssh_agent_docker_name}.sh"
        tmp_script_body = """
        #!/bin/sh
        docker run --rm --volumes-from=#{ssh_agent_docker_name} -v ~/.ssh:/.ssh -it #{@ssh_agent_image} ssh-add /root/.ssh/id_rsa
        kill -9 $(ps -p $(ps -p $PPID -o ppid=) -o ppid=) 
        """

        File.write!(tmp_script_path, tmp_script_body)
        File.chmod!(tmp_script_path, 0o700)

        System.cmd "open", ["-W", "-a", "Terminal.app", tmp_script_path]

        File.rm!(tmp_script_path)

      _ ->
        error "TODO: This operating system is not supported yet"
        Kernel.exit(:todo)
    end
  end


  defp docker_cmd_passthrough(args) do
    case System.cmd("docker", args, into: IO.binstream(:stdio, :line)) do
      {_, 0} ->
        :ok

      {_, code} ->
        {:error, code}
    end
  end


  defp info(message) do
    Mix.Shell.IO.info "[Dockerator INFO] #{message}"
  end


  defp error(message) do
    Mix.Shell.IO.error "[Dockerator ERROR] #{message}"
  end
end
