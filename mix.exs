defmodule Dockerator.Mixfile do
  use Mix.Project

  def project do
    [
      app: :dockerator,
      version: "2.0.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env == :stag or Mix.env == :prod,
      deps: deps(),
      description: description(),
      package: package(),
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:distillery, "~> 2.0", runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev},
    ]
  end

  defp description do
    """
    Tool for turning Elixir apps into Docker images without a pain.
    """
  end

  defp package do
    [
     files: ["lib", "priv", "mix.exs", "README*"],
     maintainers: ["Marcin Lewandowski"],
     licenses: ["MIT"],
     links: %{"GitHub" => "https://github.com/dockerator/dockerator-elixir"},
   ]
  end
end
