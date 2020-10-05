defmodule FourCardsGame.Application do
  @moduledoc false

  use Application
  require Logger

  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: FourCardsGame.Game.Registry},
      {Registry, keys: :unique, name: FourCardsGame.EventManager.Registry},
      {Registry, keys: :unique, name: FourCardsGame.Supervisor.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: FourCardsGame.Games},
    ]

    Logger.info("[app] initiated application")

    opts = [strategy: :one_for_one, name: FourCardsGame.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
