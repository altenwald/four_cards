defmodule FourCardsWeb.MixProject do
  use Mix.Project

  @version "1.0.0"

  def project do
    [
      app: :four_cards_web,
      version: @version,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {FourCardsWeb.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:four_cards_game, in_umbrella: true},
      {:gen_stage, "~> 1.2"},
      {:elixir_uuid, "~> 1.2"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.18"},
      {:bandit, "~> 1.8"},
      {:websock_adapter, "~> 0.5"},
      {:eqrcode, "~> 0.2"},
      {:websockex, "~> 0.5", only: :test},
      {:doctor, "~> 0.22", only: [:dev, :test], runtime: false}
    ]
  end
end
