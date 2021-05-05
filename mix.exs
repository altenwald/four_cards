defmodule FourCards.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    [
      {:observer_cli, "~> 1.6"},
      {:distillery, "~> 2.1"},
      {:dialyxir, "~> 1.1", only: :dev},
      {:ex_doc, "~> 0.24", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      release: [
        "local.hex --force",
        "local.rebar --force",
        "clean",
        "deps.get",
        "compile",
        "distillery.release --upgrade --env=prod"
      ]
    ]
  end
end
