# Dockerator for Elixir

[![Hex.pm](https://img.shields.io/hexpm/v/dockerator.svg)](https://hex.pm/packages/dockerator)
[![Hex.pm](https://img.shields.io/hexpm/dt/dockerator.svg)](https://hex.pm/packages/dockerator)

Tool for turning Elixir apps into Docker images without a pain.

## Rationale

One may say that creating a Dockerfile for an Elixir app is so easy that
creating a separate tool for such purpose is an overkill.

However, that might be not that easy if:

* You need to maintain a lot of apps and you want to ensure thay use the same
  build system without manually replicating tons of Dockerfiles.
* You use dependencies stored on private git repositories.

In such cases Dockerator will save you a lot of time.

## Features

* **Clean build environment** - It always builds the release of Elixir project 
  in the clean environment in order to ensure repeatable builds.
* **No source code in the image** - The target image will not contain the
  source code, just the compiled release.
* **SSH agent forwarding** - It can handle SSH agent forwarding so you can use 
  dependencies stored at private SSH repositories without exposing your 
  credentials.

Internally it uses [Distillery](https://github.com/bitwalker/distillery) for
building the actual release.


# Prerequisities

You need to use Elixir >= 1.4.

You need to have on your computer a [Docker](https://docker.io) installation.
The `docker` command should be callable without `sudo`.


# Usage

Add it to the dependencies, by adding the following the `deps` in `mix.exs`:

```elixir
def deps do
  [
    {:dockerator, "~> 1.1", runtime: false},
  ]
end
``` 

Moreover add the key `:dockerator_target_image` to the `app` with name of the
target Docker image.

Then fetch the dependencies:

```bash
mix deps.get
```

Create release configuration (if it is not present yet):

```bash
mix release.init
```

It will create `rel/` directory, add it to git:

```bash
git add rel/
```


Then you can just call the following command each time you need to assemble
a Docker image tagged as `latest`:

```bash
mix dockerate
```

If you want to make the actual release, please increase version in the
`mix.exs` (potentially you want to also tag the code in git) and then run

```bash
mix dockerate release
```

The Docker image will use version from `mix.exs` as a tag.

You probably want to also change the Mix environment, just prefix the
commands with MIX_ENV=env, e.g.:


```bash
MIX_ENV=prod mix dockerate release
```



# Configuration

You can use the following settings in the `project` of the `mix.exs` in order
to configure Dockerator:

* `:dockerator_target_image` - (mandatory) - a string containing target
  Docker image name, e.g. `"myaccount/my_app"`.
* `:dockerator_base_image` - (optional) - a string or keyword list containing 
  name of a base Docker image name used for build and release. If it is
  a string, it will use provided name for both build and release. If it is
  a keyword list, you can specify two keys `:build` or/and `:release` to
  specify different images for these two phases. Defaults to 
  `elixir:latest`. It is strongly encouraged to change this to the particular
  [Elixir version](https://hub.docker.com/r/library/elixir/tags/) to have
  repeatable builds.
* `:dockerator_ssh_agent` - (optional) - a boolean indicating whether
  we should use SSH agent for the build. Defaults to `false`. Turn it on
  if you're using dependencies that are hosted on private git/SSH repositories.
* `:dockerator_source_dirs` - (optional) - a list of strings containing a list
  of source directories that will be copied to the build image. Defaults to
  `["config", "lib", "rel", "priv", "web"]`.
* `:dockerator_release_extra_docker_commands` - optional - a list of strings that
  will contain extra commands that will be added to the release image. For
  example you can add something like `["EXPOSE 4000"]`. 

## Example

For example your `mix.exs` might look like this after the changes:

```elixir
defmodule MyApp.Mixfile do
  use Mix.Project

  def project do
    [app: :my_app,
     version: "0.1.0",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(),
     dockerator_ssh_agent: true,
     dockerator_release_extra_docker_commands: [
       "EXPOSE 4000",
       "RUN apt-get update && apt-get install somepackage",
     ],
     dockerator_source_dirs: ["config", "lib", "rel", "priv", "web", "extra"],
     dockerator_base_image: [build: "elixir:1.4.5", release: "ubuntu:xenial"],
     dockerator_target_image: "myaccount/my_app",
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {MyApp, []}]
  end

  defp deps do
    [
      {:dockerator, "~> 1.1", runtime: false},
    ]
  end
end
```


# Limitations

* Currently it assumes that release name defined in `rel/config.exs` is 
  the same as app name defined in the mix.exs.
* It has to rely on base image based on any `apt`-compatible system, such as 
  Ubuntu or Debian, however this is unimportant if you don't use git-based 
  dependencies. This is because if it won't find `git` command in the base
  image it will invoke `apt-get install git`.
* At the moment it will not handle SSH agent on other platforms than Mac OS X.
  However it should be quite trivial to add others.


# Let me believe that Karma returns!

Developers are humans, too, we also need to pay bills from time to time. If you
wish to repay time and effort thay you have saved thanks to this piece of code,
you can click one of this nice, shiny buttons below:

| Paypal | Bitcoin | Beerpay |
| :----: | :-----: | :-----: |
| [![](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=5BF9TT5YQNU5J) | [![](https://i.imgur.com/dFkg3fw.png)](https://i.imgur.com/5VJeR9h.png)<br> 1LHsmP3odWxu1bzUfe2ydrewArB72XbN7n | [![Go to Beerpay](https://beerpay.io/mspanc/jumbo/badge.svg)](https://beerpay.io/mspanc/jumbo) |


# Authors

Marcin Lewandowski, marcin@saepia.net


# License

MIT