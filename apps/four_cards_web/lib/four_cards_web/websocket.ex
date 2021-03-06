defmodule FourCardsWeb.Websocket do
  require Logger

  alias FourCardsWeb.Request

  @default_deck "napoletane"

  @behaviour :cowboy_websocket

  @impl :cowboy_websocket
  def init(req, opts) do
    Logger.info("[websocket] init req => #{inspect(req)}")
    remote_ip = Request.remote_ip(req)
    {:cowboy_websocket, req, [{:remote_ip, remote_ip} | opts]}
  end

  @impl :cowboy_websocket
  def websocket_init(remote_ip: remote_ip) do
    vsn = FourCardsWeb.Application.vsn()
    reply = Jason.encode!(%{"type" => "vsn", "vsn" => vsn})
    state = %{name: nil, remote_ip: remote_ip, deck: @default_deck}
    {:reply, {:text, reply}, state}
  end

  @doc """
  The information received by this function is sent from the browser
  directly to the websocket to be handle by the websocket. Most of the
  actions have direct impact into the game.
  """
  @impl :cowboy_websocket
  def websocket_handle({:text, msg}, state) do
    msg
    |> Jason.decode!()
    |> process_data(state)
  end

  def websocket_handle(_any, state) do
    {:reply, {:text, "eh?"}, state}
  end

  @doc """
  The information received by websocket is from "info" is sent mainly
  by the `FourCardsWeb.Consumer` consumer regarding the information received
  from the Game where we did our subscription.
  """
  @impl :cowboy_websocket
  def websocket_info({:send, data}, state) do
    {:reply, {:text, data}, state}
  end

  def websocket_info({:timeout, _ref, msg}, state) do
    {:reply, {:text, msg}, state}
  end

  def websocket_info({:join, player}, state) do
    msg = %{"type" => "join", "username" => player}
    {:reply, {:text, Jason.encode!(msg)}, state}
  end

  def websocket_info({:disconnected, player}, state) do
    msg = %{"type" => "leave", "username" => player}
    {:reply, {:text, Jason.encode!(msg)}, state}
  end

  def websocket_info(:dealt, state) do
    msg = send_update_msg("dealt", state.name, state.deck)
    {:reply, {:text, Jason.encode!(msg)}, state}
  end

  def websocket_info({:turn, _username, previous}, state) do
    msg =
      send_update_msg("turn", state.name, state.deck)
      |> Map.put("previous", previous)

    {:reply, {:text, Jason.encode!(msg)}, state}
  end

  def websocket_info({:game_over, winner}, state) do
    msg =
      send_update_msg("game_over", state.name, state.deck)
      |> Map.put("winner", winner)

    {:reply, {:text, Jason.encode!(msg)}, state}
  end

  def websocket_info({:pass, player_name}, state) do
    msg =
      send_update_msg("pass", state.name, state.deck)
      |> Map.put("previous", player_name)

    {:reply, {:text, Jason.encode!(msg)}, state}
  end

  def websocket_info({:capture, _player_name, _where, _captured_card, _matching}, state) do
    msg = send_update_msg("update", state.name, state.deck)
    {:reply, {:text, Jason.encode!(msg)}, state}
  end

  def websocket_info(info, state) do
    Logger.info("info => #{inspect(info)}")
    {:ok, state}
  end

  defp send_update_msg(event, name, deck) do
    %{
      "type" => event,
      "hand" => get_cards(FourCardsGame.get_hand(name), deck),
      "shown" => get_cards(FourCardsGame.get_shown(name), deck),
      "captured" => get_capture_cards(FourCardsGame.get_captured(name), deck),
      "players" => get_players(FourCardsGame.players(name)),
      "playing" => get_playing_card(FourCardsGame.playing_card?(name), deck),
      "turn" => FourCardsGame.whose_turn_is_it?(name),
      "deck" => FourCardsGame.deck_cards_num(name)
    }
  end

  defp get_playing_card(nil, _deck), do: nil
  defp get_playing_card({:error, _}, _deck), do: nil
  defp get_playing_card(card, deck), do: get_card(card, deck)

  defp get_capture_cards(players, deck) do
    Enum.reduce(players, %{}, fn
      {_name, nil}, acc -> acc
      {name, card}, acc -> Map.put(acc, name, get_card(card, deck))
    end)
  end

  defp get_card({type, number}, deck) do
    "/img/cards/#{deck}/#{type}_#{number}.svg"
  end

  defp get_cards(cards, deck) do
    for {_k, card} <- cards do
      get_card(card, deck)
    end
  end

  defp get_players(players) do
    for {name, captured_cards} <- players do
      %{
        "username" => name,
        "captured_cards" => captured_cards
      }
    end
  end

  defp process_data(%{"type" => "ping"}, state) do
    {:reply, {:text, Jason.encode!(%{"type" => "pong"})}, state}
  end

  defp process_data(%{"type" => "create"}, state) do
    name = UUID.uuid4()
    {:ok, _game_pid} = FourCardsGame.start(name)
    msg = %{"type" => "id", "id" => name}
    state = %{state | name: name}
    {:reply, {:text, Jason.encode!(msg)}, state}
  end

  defp process_data(
         %{"type" => "join", "name" => name, "username" => username},
         state
       ) do
    if FourCardsGame.exists?(name) do
      FourCardsWeb.Application.start_consumer(name, self())
      username = String.trim(username)

      if not FourCardsGame.is_game_over?(name) do
        replies =
          for {player, _} <- FourCardsGame.players(name), player != username do
            {:text, Jason.encode!(%{"type" => "join", "username" => player})}
          end

        FourCardsGame.join(name, username)
        {:reply, replies, %{state | name: name}}
      else
        FourCardsGame.restart(name)
        {:ok, state}
      end
    else
      Logger.warn("doesn't exist #{inspect(name)}")
      msg = %{"type" => "notfound", "error" => true}
      {:reply, {:text, Jason.encode!(msg)}, state}
    end
  end

  defp process_data(%{"type" => "deal"}, %{name: name} = state) do
    FourCardsGame.deal(name)
    {:ok, state}
  end

  defp process_data(%{"type" => "play_from", "card" => card}, state) when is_integer(card) do
    FourCardsGame.play_from(state.name, card)
    msg = send_update_msg("update", state.name, state.deck)
    {:reply, {:text, Jason.encode!(msg)}, state}
  end

  defp process_data(%{"type" => "play_to", "card" => card, "where" => where}, state) do
    where = case where do
      "player" -> :player
      _ -> :shown
    end
    FourCardsGame.play_to(state.name, where, card)
    msg = send_update_msg("update", state.name, state.deck)
    {:reply, {:text, Jason.encode!(msg)}, state}
  end

  defp process_data(%{"type" => "pass"}, state) do
    FourCardsGame.pass(state.name)
    {:ok, state}
  end

  defp process_data(%{"type" => "restart"}, state) do
    FourCardsGame.restart(state.name)
    {:ok, state}
  end
end
