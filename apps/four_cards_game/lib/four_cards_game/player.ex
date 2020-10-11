defmodule FourCardsGame.Player do
  alias FourCardsGame.{Game, Player}

  @type t :: %__MODULE__{
    pid: pid(),
    name: String.t(),
    hand_cards: Game.cards(),
    captured_cards: Game.cards()
  }

  defstruct pid: nil,
            name: nil,
            hand_cards: [],
            captured_cards: []

  def new(name, pid) do
    %Player{name: name, pid: pid}
  end

  def has_name_or_pid(%Player{name: name}, name, _pid), do: true
  def has_name_or_pid(%Player{pid: pid}, _name, pid), do: true
  def has_name_or_pid(_player, _name, _pid), do: false

  def info(%Player{name: name, captured_cards: captured_cards}) do
    {name, length(captured_cards)}
  end

  def info(players) when is_list(players) do
    for player <- players, do: info(player)
  end

  def valid_name?(_players, ""), do: false
  def valid_name?(players, username) do
    not Enum.any?(players, fn
      %Player{name: ^username} -> true
      %Player{} -> false
    end)
  end

  def get_by_pid(players, pid) do
    case Enum.filter(players, &(&1.pid == pid)) do
      [player] -> player
      [] -> nil
    end
  end

  def get_by_name(players, name) do
    case Enum.filter(players, &(&1.name == name)) do
      [player] -> player
      [] -> nil
    end
  end

  def get_captured(%Player{captured_cards: captured}), do: captured

  def get_captured([%Player{} | _] = players) do
    for %Player{name: name, captured_cards: captured} <- players do
      case captured do
        [] -> {name, nil}
        [card | _] -> {name, card}
      end
    end
  end

  def add_captured(%Player{captured_cards: captured} = player, ccards) when is_list(ccards) do
    %Player{player | captured_cards: ccards ++ captured}
  end

  def add_captured(%Player{captured_cards: captured} = player, ccard) when is_tuple(ccard) do
    %Player{player | captured_cards: [ccard | captured]}
  end

  def get_hand(%Player{hand_cards: cards}), do: cards

  def get_hand_card(%Player{hand_cards: hand_cards} = player, num) do
    playing_card = Enum.at(hand_cards, num)
    hand_cards = hand_cards -- [playing_card]
    {playing_card, %Player{player | hand_cards: hand_cards}}
  end

  def add_hand_card(%Player{} = player, nil), do: player
  def add_hand_card(%Player{hand_cards: hand_cards} = player, card) do
    %Player{player | hand_cards: [card | hand_cards]}
  end

  def reset_captured(%Player{} = player) do
    %Player{player | captured_cards: []}
  end

  def reset_hand_cards(%Player{} = player) do
    %Player{player | hand_cards: []}
  end

  def reset_hand_cards([%Player{} | _] = players) do
    for player <- players, do: reset_hand_cards(player)
  end

  def replace_pid(%Player{pid: pid} = player, pid), do: player
  def replace_pid(%Player{pid: nil} = player, pid) do
    %Player{player | pid: pid}
  end
  def replace_pid(%Player{pid: old_pid} = player, pid) do
    Process.exit(old_pid, :kicked)
    %Player{player | pid: pid}
  end

  @doc """
  Replace the player for a modification of itself keeping it in the same
  position it was.
  """
  def update(players, changed_player) do
    for player <- players do
      if changed_player.name == player.name do
        changed_player
      else
        player
      end
    end
  end

  def get_winner(players) do
    [{_, winner} | _] =
      players
      |> Enum.map(fn p -> {length(p.captured_cards), p.name} end)
      |> Enum.sort()
      |> Enum.reverse()

    winner
  end
end
