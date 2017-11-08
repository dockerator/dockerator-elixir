defmodule Dockerator.Mixfile do
  use Mix.Project

  def project do
    [
      app: :dockerator,
      version: "1.0.0",
      elixir: "~> 1.4",
      start_permanent: Mix.env == :stag or Mix.env == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:distillery, "~> 1.5", runtime: false}
    ]
  end
end
