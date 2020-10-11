defmodule FourCardsWeb.Application do
  @moduledoc false

  use Application

  require Logger

  alias FourCardsGame.EventManager

  @port 8080

  @consumer_sup FourCardsWeb.Consumers

  def start(_type, _args) do
    port_number = Application.get_env(:four_cards_web, :port, @port)

    children = [
      Plug.Cowboy.child_spec(
        scheme: :http,
        plug: FourCardsWeb.Router,
        options: [port: port_number, dispatch: dispatch()]
      ),
      {DynamicSupervisor, strategy: :one_for_one, name: @consumer_sup}
    ]

    Logger.info("[app] initiated application")

    opts = [strategy: :one_for_one, name: FourCardsWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def start_consumer(name, websocket) do
    producer = EventManager.get_pid(name)
    args = [producer, websocket]
    DynamicSupervisor.start_child(@consumer_sup, {FourCardsWeb.Consumer, args})
  end

  def vsn do
    to_string(Application.spec(:four_cards_web)[:vsn])
  end

  defp dispatch do
    [
      {:_,
        [
          {"/websession", FourCardsWeb.Websocket, []},
          {"/kiosksession", FourCardsWeb.Kiosk.Websocket, []},
          {:_, Plug.Cowboy.Handler, {FourCardsWeb.Router, []}}
        ]
      }
    ]
  end
end
