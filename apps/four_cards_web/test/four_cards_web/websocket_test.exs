defmodule FourCardsWeb.WebsocketTest do
  # Real server (Bandit) and real WebSocket connections: the whole path from the browser to the game.
  use ExUnit.Case, async: false

  defmodule Client do
    use WebSockex

    def start(path, parent) do
      WebSockex.start("ws://127.0.0.1:4116#{path}", __MODULE__, parent)
    end

    def push(pid, map), do: WebSockex.send_frame(pid, {:text, Jason.encode!(map)})

    @impl WebSockex
    def handle_frame({:text, text}, parent) do
      send(parent, {:frame, self(), Jason.decode(text)})
      {:ok, parent}
    end
  end

  defp connect do
    {:ok, pid} = Client.start("/websession", self())
    # the first message of every connection is the version of the server
    assert {"vsn", %{"vsn" => vsn}} = receive_frame(pid)
    assert vsn == FourCardsWeb.Application.vsn()
    pid
  end

  defp receive_frame(pid, timeout \\ 2_000) do
    receive do
      {:frame, ^pid, {:ok, %{"type" => type} = msg}} -> {type, msg}
      {:frame, ^pid, {:ok, other}} -> {:other, other}
      {:frame, ^pid, {:error, _}} -> {:invalid, nil}
    after
      timeout -> flunk("no message received")
    end
  end

  test "a player answers ping and creates a game" do
    player = connect()

    Client.push(player, %{"type" => "ping"})
    assert {"pong", _} = receive_frame(player)

    Client.push(player, %{"type" => "create"})
    assert {"id", %{"id" => id}} = receive_frame(player)
    assert FourCardsGame.exists?(id)
  end

  test "a player joining an unknown game is told it was not found" do
    player = connect()
    Client.push(player, %{"type" => "join", "name" => "does-not-exist", "username" => "ana"})
    assert {"notfound", %{"error" => true}} = receive_frame(player)
  end

  test "messages that are not JSON are answered without crashing the connection" do
    player = connect()
    WebSockex.send_frame(player, {:text, "not json"})
    # the answer is the plain text "eh?", which is not JSON
    assert {:invalid, nil} = receive_frame(player)
    Client.push(player, %{"type" => "ping"})
    assert {"pong", _} = receive_frame(player)
  end

  test "the players of a game see each other join" do
    first = connect()
    Client.push(first, %{"type" => "create"})
    assert {"id", %{"id" => id}} = receive_frame(first)

    Client.push(first, %{"type" => "join", "name" => id, "username" => "ana"})
    assert {"join", %{"username" => "ana"}} = receive_frame(first)

    second = connect()
    Client.push(second, %{"type" => "join", "name" => id, "username" => "luis"})

    # the newcomer is told who was already there, and the one who was there is told about the newcomer
    assert {"join", %{"username" => "ana"}} = receive_frame(second)
    assert {"join", %{"username" => "luis"}} = receive_frame(first)
  end
end
