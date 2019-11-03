defmodule FourCards do
  @moduledoc """
  Documentation for FourCards.
  """
  use GenStage

  alias FourCards.{Game, EventManager}
  alias IO.ANSI

  defp ask(prompt) do
    "#{prompt}> "
    |> IO.gets()
    |> String.trim()
    |> String.downcase()
  end

  defp ask_num(prompt) do
    try do
      ask(prompt)
      |> String.to_integer()
    rescue
      _ in ArgumentError -> ask_num(prompt)
    end
  end

  def start(name \\ __MODULE__) do
    Game.start name
    pid = EventManager.get_pid(name)
    GenStage.start_link __MODULE__, [pid, self()]
    user = ask "name"
    waiting(name, user)
  end

  def init([producer, game]) do
    {:consumer, game, subscribe_to: [producer]}
  end

  def handle_events(events, _from, game) do
    for event <- events do
      case event do
        {:join, name} ->
          IO.puts "event: join #{name}"
        {:game_over, winner} ->
          IO.puts "\nG A M E   O V E R\n\n#{winner} WINS!!!"
          send game, event
        _ ->
          send game, event
      end
    end
    {:noreply, [], game}
  end

  def waiting(name, user) do
    Game.join name, user
    IO.puts "Note that 'deal' should be made when everyone is onboarding."
    case ask("deal? [Y/n]") do
      "n" ->
        waiting(name, user)
      _ ->
        Game.deal(name)
        playing(name, user)
    end
  end

  def playing(name \\ __MODULE__, user) do
    if Game.is_game_over?(name) do
      IO.puts "GAME OVER!"
    else
      cards = Game.get_shown(name)
      IO.puts [ANSI.reset(), ANSI.clear()]
      IO.puts "Four Cards - #{vsn()}"
      IO.puts "--------------------"
      draw_players(Game.players(name))
      IO.puts ["\nShown -->",
                "\nIn deck: #{Game.deck_cards_num(name)}\n"]
      draw_cards(cards)
      IO.puts "Captured -->"
      draw_cards(Game.get_captured(name))
      playing_card = Game.playing_card?(name)
      if playing_card != nil and playing_card != {:error, :not_your_turn} do
        IO.puts "Playing card -->"
        draw_card(playing_card)
      end
      IO.puts "Your hand -->"
      cards = Game.get_hand(name)
      draw_cards(cards)
      if Game.is_my_turn?(name) do
        choose_option(name, user, cards)
      else
        IO.puts "waiting for your turn..."
        wait_for_turn(name, user)
      end
    end
  end

  def capturing(name, user) do
    shown_cards = Game.get_shown(name)
    IO.puts [ANSI.reset(), ANSI.clear()]
    IO.puts "Four Cards - #{vsn()}"
    IO.puts "--------------------"
    draw_players(Game.players(name))
    IO.puts ["\nShown -->",
              "\nIn deck: #{Game.deck_cards_num(name)}\n"]
    draw_cards(shown_cards)
    IO.puts "Captured -->"
    draw_cards(Game.get_captured(name))
    playing_card = Game.playing_card?(name)
    if playing_card do
      IO.puts "Playing card -->"
      draw_card(playing_card)
    end
    choose_capture_option(name, user, shown_cards)
  end

  defp choose_option(name, user, cards) do
    case ask("[C]hoose [Q]uit") do
      "c" ->
        num = ask_num("card")
        Game.play_from(name, num)
        capturing(name, user)
      "q" ->
        :ok
      _ ->
        choose_option(name, user, cards)
    end
  end

  defp choose_capture_option(name, user, cards) do
    case ask("[D]rop [C]hoose [T]heft [B]ack") do
      "d" ->
        Game.pass(name)
        playing(name, user)
      "c" ->
        num = ask_num("card")
        Game.play_to(name, :shown, num)
        capturing(name, user)
      "t" ->
        from_name = ask("card")
        Game.play_to(name, :player, from_name)
        capturing(name, user)
      "b" ->
        playing(name, user)
      _ ->
        choose_capture_option(name, user, cards)
    end
  end

  defp wait_for_turn(name, user) do
    receive do
      {:turn, _whatever_user, _previous_one} ->
        playing(name, user)
      {:game_over, _} ->
        :ok
      other ->
        IO.puts("event: #{inspect other}")
        wait_for_turn(name, user)
    end
  end

  def vsn do
    to_string(Application.spec(:four_cards)[:vsn])
  end

  defp to_kind(:copa), do: [ANSI.red_background(), ANSI.black()]
  defp to_kind(:basto), do: [ANSI.green_background(), ANSI.black()]
  defp to_kind(:espada), do: [ANSI.blue_background(), ANSI.white()]
  defp to_kind(:oro), do: [ANSI.light_yellow_background(), ANSI.black()]

  defp to_number(n) when is_integer(n), do: " #{n} "
  defp to_number(:sota), do: " S "
  defp to_number(:caballo), do: " C "
  defp to_number(:rey), do: " R "

  defp draw_players(players) do
    [
      "+----------------------+-----+\n",
      for {name, cards_num} <- players do
        [
          "| ",
          name
          |> String.slice(0..19)
          |> String.pad_trailing(20),
          " | ",
          cards_num
          |> to_string()
          |> String.pad_leading(3),
          " |\n"
        ]
      end,
      "+----------------------+-----+",
    ] |> IO.puts()
  end

  defp draw_card({kind, number}) do
    color = to_kind(kind)
    symbol = to_number(number)
    [
      color, "+-----+", ANSI.reset(), "\n",
      color, "|     |", ANSI.reset(), "\n",
      color, "| #{symbol} |", ANSI.reset(), "\n",
      color, "|     |", ANSI.reset(), "\n",
      color, "+-----+", ANSI.reset(), "\n"
    ] |> IO.puts()
  end

  defp draw_cards(cards) do
    cards = for {i, {kind, num}} <- cards, do: {i, to_kind(kind), to_number(num)}
    [
      for({i, _color, _} <- cards, do: ["#{pad(i)}"]), "\n",
      for({_i, color, _} <- cards, do: [color, "+-----+", ANSI.reset()]), "\n",
      for({_i, color, _}  <- cards, do: [color, "|     |", ANSI.reset()]), "\n",
      for({_i, color, symbol}  <- cards, do: [color, "| #{symbol} |", ANSI.reset()]), "\n",
      for({_i, color, _}  <- cards, do: [color, "|     |", ANSI.reset()]), "\n",
      for({_i, color, _}  <- cards, do: [color, "+-----+", ANSI.reset()]), "\n"
    ] |> IO.puts()
  end

  defp pad(str) when is_binary(str) do
    str
    |> String.slice(0, 5)
    |> String.pad_trailing(6)
    |> String.pad_leading(7)
  end
  defp pad(i) when i > 10, do: pad(to_string(i))
  defp pad(i), do: pad(" #{i}")
end
