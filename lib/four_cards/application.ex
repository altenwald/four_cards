defmodule FourCards.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  # @port 1234

  def start(_type, _args) do
    # List all child processes to be supervised
    # port_number = Application.get_env(:zero, :port, @port)

    children = [
      {Registry, keys: :unique, name: FourCards.Game.Registry},
      {Registry, keys: :unique, name: FourCards.EventManager.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: FourCards.Games},
    ]

    Logger.info "[app] initiated application"

    opts = [strategy: :one_for_one, name: FourCards.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
