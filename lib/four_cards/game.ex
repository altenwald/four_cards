defmodule FourCards.Game do
  use GenStateMachine, callback_mode: :state_functions

  @card_kind ~w[ basto copa oro espada ]a
  @card_number [1, 2, 3, 4, 5, 6, 7, :sota, :caballo, :rey]

  @initial_cards 4
  @max_num_players 5

  @max_menu_time 3_600_000
  @max_game_time 21_600_000
  @max_ended_time 1_800_000

  @game_registry FourCards.Game.Registry
  @game_supervisor FourCards.Games

  alias FourCards.{Game, EventManager}

  @type name :: String.t

  @type card :: {card_kind, card_number}
  @type card_kind :: :bastos | :copas | :oros | :espadas
  @type card_number :: 1..7 | :sota | :caballo | :rey
  @type cards :: [card]
  @type hand_cards :: [card]
  @type captured_cards :: [card]

  defmodule Player do
    defstruct pid: nil,
              name: nil,
              hand_cards: [],
              captured_cards: []
  end

  @type players :: [Player.t]

  defstruct players: [],
            deck: [],
            shown: [],
            playing_card: nil,
            matching: 0,
            name: nil

  def child_spec(init_args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [init_args]},
      restart: :transient
    }
  end

  defp via(game) do
    {:via, Registry, {@game_registry, game}}
  end

  def start_link(name) do
    GenStateMachine.start_link __MODULE__, [name], name: via(name)
  end

  def start(game) do
    DynamicSupervisor.start_child @game_supervisor, {__MODULE__, game}
  end

  def exists?(game) do
    case Registry.lookup(@game_registry, game) do
      [{_pid, nil}] -> true
      [] -> false
    end
  end

  defp cast(name, args), do: GenStateMachine.cast via(name), args
  defp call(name, args), do: GenStateMachine.call via(name), args

  def join(name, player_name), do: cast name, {:join, self(), player_name}
  def deal(name), do: cast name, :deal
  def get_hand(name), do: call name, :get_hand
  def get_players_number(name), do: call name, :players_num
  def get_shown(name), do: call name, :get_shown
  def get_captured(name), do: call name, :get_captured

  def playing_card?(name), do: call name, :playing_card
  def play_from(name, from_num), do: call name, {:play_from, from_num}
  def play_to(name, where, to_num), do: call name, {:play_to, where, to_num}
  def pass(name), do: call name, :pass

  def is_my_turn?(name), do: call name, :is_my_turn?
  def players(name), do: call name, :players
  def whose_turn_is_it?(name), do: call name, :whose_turn_is_it?
  def deck_cards_num(name), do: call name, :deck_cards_num
  def restart(name), do: cast name, :restart
  def valid_name?(name, username), do: call name, {:valid_name?, username}
  def is_game_over?(name), do: call name, :is_game_over?

  def get_pid(game) do
    [{pid, _}] = Registry.lookup(@game_registry, game)
    pid
  end

  def stop(name) do
    EventManager.stop(name)
    GenStateMachine.stop via(name)
  end

  @impl GenStateMachine
  def init([name]) do
    EventManager.start_link(name)
    game = %Game{deck: shuffle_cards(), name: name}
    {:ok, :waiting_players, game, [{:state_timeout, @max_menu_time, :game_over}]}
  end

  @impl GenStateMachine
  def code_change(_old_vsn, state_name, state_data, _extra) do
    {:ok, state_name, state_data}
  end

  ## State: waiting for players

  def waiting_players(:cast, {:join, _, _}, %Game{players: players})
      when length(players) > @max_num_players do
    :keep_state_and_data
  end
  def waiting_players(:cast, {:join, player_pid, player_name}, game) do
    case {List.keyfind(game.players, player_name, 1),
          List.keyfind(game.players, player_pid, 0)} do
      {nil, nil} ->
        Process.monitor player_pid
        EventManager.notify(game.name, {:join, player_name})
        player = %Player{pid: player_pid, name: player_name}
        {:keep_state, %Game{game | players: [player|game.players]}}
      _ ->
        :keep_state_and_data
    end
  end

  def waiting_players(:cast, :deal, %Game{players: p}) when length(p) < 2 do
    :keep_state_and_data
  end
  def waiting_players(:cast, :deal, game) do
    game = give_cards(game)
    {:next_state, :playing, game, [{:state_timeout, @max_game_time, :game_over}]}
  end

  def waiting_players({:call, from}, :is_game_over?, _game) do
    {:keep_state_and_data, [{:reply, from, false}]}
  end

  def waiting_players({:call, from}, :players_num, %Game{players: players}) do
    {:keep_state_and_data, [{:reply, from, length(players)}]}
  end

  def waiting_players({:call, from}, :players, %Game{players: players}) do
    players = for player <- players do
      {player.name, length(player.captured_cards)}
    end
    {:keep_state_and_data, [{:reply, from, players}]}
  end

  def waiting_players({:call, from}, {:valid_name?, username}, game) do
    reply = not Enum.any?(game.players, fn %Player{name: ^username} -> true
                                           %Player{} -> false end)
    {:keep_state_and_data, [{:reply, from, reply}]}
  end

  def waiting_players(:info, {:DOWN, _ref, :process, player_pid, _reason},
                      %Game{players: players} = game) do
    [player] = Enum.filter(players, &(&1.pid == player_pid))
    EventManager.notify(game.name, {:disconnected, player.name})
    {:keep_state, %Game{game | players: players -- [player]}}
  end

  def waiting_players(:cast, :restart, _game) do
    :keep_state_and_data
  end

  ## State: playing

  def playing({:call, from}, :is_game_over?, _game) do
    {:keep_state_and_data, [{:reply, from, false}]}
  end

  def playing(:cast, {:join, player_pid, name}, %Game{players: players} = game) do
    players = case find_player_by_name(players, name) do
      nil ->
        players
      %Player{pid: ^player_pid, name: ^name} ->
        players
      %Player{name: ^name} = player ->
        if player.pid != nil do
          Process.exit(player.pid, :kicked)
        end
        Process.monitor player_pid
        EventManager.notify(game.name, {:join, name})
        update_player(players, %Player{player | pid: player_pid})
    end
    {:keep_state, %Game{game | players: players}}
  end

  def playing(:cast, :deal, game) do
    EventManager.notify(game.name, :dealt)
    :keep_state_and_data
  end

  def playing({:call, {player_pid, _} = from}, :get_hand,
              %Game{players: players}) do
    reply = case find_player_by_pid(players, player_pid) do
      nil ->
        :not_found
      %Player{hand_cards: cards} ->
        cards
        |> Enum.with_index(1)
        |> List.foldl(%{}, fn {v, k}, acc -> Map.put_new(acc, k, v) end)
    end
    {:keep_state_and_data, [{:reply, from, reply}]}
  end

  def playing({:call, from}, :players_num, %Game{players: players}) do
    {:keep_state_and_data, [{:reply, from, length(players)}]}
  end

  def playing({:call, from}, :deck_cards_num, %Game{deck: deck}) do
    {:keep_state_and_data, [{:reply, from, length(deck)}]}
  end

  def playing({:call, from}, :get_shown, %Game{shown: cards}) do
    reply = cards
            |> Enum.with_index(1)
            |> List.foldl(%{}, fn {v, k}, acc -> Map.put_new(acc, k, v) end)
    {:keep_state_and_data, [{:reply, from, reply}]}
  end

  def playing({:call, from}, :get_captured, %Game{players: players}) do
    cards = for %Player{name: name, captured_cards: captured} <- players do
      case captured do
        [] -> {name, nil}
        [card|_] -> {name, card}
      end
    end
    {:keep_state_and_data, [{:reply, from, cards}]}
  end

  def playing({:call, {from_pid, _} = from}, :is_my_turn?,
              %Game{players: [%Player{pid: pid}|_]}) do
    {:keep_state_and_data, [{:reply, from, from_pid == pid}]}
  end

  def playing({:call, from}, :whose_turn_is_it?, %Game{players: [player|_]}) do
    {:keep_state_and_data, [{:reply, from, player.name}]}
  end

  def playing({:call, from}, :players, %Game{players: players}) do
    players = for player <- players do
      {player.name, length(player.captured_cards)}
    end
    {:keep_state_and_data, [{:reply, from, players}]}
  end

  ## from here... it should be "your turn"
  def playing({:call, {player_pid, _} = from}, _action,
              %Game{players: [%Player{pid: other_pid}|_]})
      when player_pid != other_pid do
    {:keep_state_and_data, [{:reply, from, {:error, :not_your_turn}}]}
  end

  def playing({:call, from}, :playing_card, game) do
    {:keep_state_and_data, [{:reply, from, game.playing_card}]}
  end

  def playing({:call, from}, {:play_from, from_num},
              %Game{players: [%Player{hand_cards: cards}|_]})
      when length(cards) < from_num or from_num <= 0 do
    {:keep_state_and_data, [{:reply, from, {:error, :invalid_number}}]}
  end
  def playing({:call, from}, {:play_from, _num},
              %Game{matching: i}) when i > 0 do
    {:keep_state_and_data, [{:reply, from, {:error, :matching}}]}
  end
  def playing({:call, from}, {:play_from, from_num},
              %Game{players: [player|_players],
                    playing_card: nil} = game) do
    hand_cards = player.hand_cards
    playing_card = Enum.at(hand_cards, from_num - 1)
    hand_cards = hand_cards -- [playing_card]
    players = game.players
              |> update_player(%Player{player | hand_cards: hand_cards})
    game = %Game{game | players: players,
                        playing_card: playing_card,
                        matching: 0}
    {:keep_state, game,  [{:reply, from, :ok}]}
  end
  def playing({:call, from}, {:play_from, from_num},
              %Game{players: [player|_players],
                    playing_card: playing_card} = game) do
    hand_cards = player.hand_cards ++ [playing_card]
    players = game.players
              |> update_player(%Player{player | hand_cards: hand_cards})
    game = %Game{game | players: players, playing_card: nil}
    playing({:call, from}, {:play_from, from_num}, game)
  end

  def playing({:call, from}, {:play_to, _where, _to_num},
              %Game{playing_card: nil}) do
    {:keep_state_and_data, [{:reply, from, {:error, :choose_card_first}}]}
  end
  def playing({:call, from}, {:play_to, :shown, to_num}, %Game{shown: cards})
      when length(cards) < to_num or to_num <= 0 do
    {:keep_state_and_data, [{:reply, from, {:error, :invalid_number}}]}
  end
  def playing({:call, from}, {:play_to, :shown, to_num},
              %Game{matching: m, players: [player|_]} = game) do
    {_kind, number} = game.playing_card
    number = increase_number(m, number)
    case Enum.at(game.shown, to_num - 1) do
      {_kind, ^number} = captured_card ->
        shown_cards = game.shown -- [captured_card]
        ccards = [game.playing_card|player.captured_cards]
        players = game.players
                  |> update_player(%Player{player | captured_cards: ccards})
        m = m + 1
        game = %Game{game | players: players,
                            matching: m,
                            playing_card: captured_card,
                            shown: shown_cards}
        EventManager.notify(game.name, {:capture, player.name, :shown, captured_card, m})
        {:keep_state, game, [{:reply, from, :ok}]}
      {_kind, _number} ->
        {:keep_state_and_data, [{:reply, from, {:error, :invalid_card}}]}
    end
  end
  def playing({:call, from}, {:play_to, :player, _name}, %Game{matching: 0}) do
    {:keep_state_and_data, [{:reply, from, {:error, :illegal_move}}]}
  end
  def playing({:call, from}, {:play_to, :player, player_name},
              %Game{matching: m, players: [player|players]} = game) do
    {_kind, number} = game.playing_card
    number = increase_number(m, number)
    case Enum.filter(players, &(&1.name == player_name)) do
      [%Player{captured_cards: [{_, ^number} = ccard|ccards]} = cplayer] ->
        captured_cards = [game.playing_card] ++ ccards ++ player.captured_cards
        players = game.players
                  |> update_player(%Player{cplayer | captured_cards: []})
                  |> update_player(%Player{player | captured_cards: captured_cards})
        m = m + 1
        game = %Game{game | players: players, matching: m, playing_card: ccard}
        EventManager.notify(game.name, {:capture, player.name, :player, player_name, m})
        {:keep_state, game, [{:reply, from, :ok}]}
      [_] ->
        {:keep_state_and_data, [{:reply, from, {:error, :invalid_player_card}}]}
      [] ->
        {:keep_state_and_data, [{:reply, from, {:error, :invalid_player}}]}
    end
  end

  def playing({:call, from}, :pass, %Game{playing_card: nil}) do
    {:keep_state_and_data, [{:reply, from, {:error, :choose_card_first}}]}
  end
  def playing({:call, from}, :pass,
               %Game{players: [player|_],
                     matching: 0,
                     playing_card: playing_card} = game) do
    previous = player.name
    game = game
           |> drop_card()
           |> pick_card()
           |> next_player()
    %Game{players: [next_player|_]} = game
    EventManager.notify(game.name, {:drop, previous, playing_card})
    EventManager.notify(game.name, {:pick_from_deck, previous})
    EventManager.notify(game.name, {:turn, next_player.name, previous})
    if game_ends?(game) do
      EventManager.notify(game.name, {:game_over, who_wins?(game)})
      actions = [{:reply, from, :game_over},
                {:state_timeout, @max_ended_time, :terminate}]
      {:next_state, :ended, game, actions}
    else
      {:keep_state, game, [{:reply, from, :ok}]}
    end
  end
  def playing({:call, from}, :pass,
              %Game{players: [player|_],
                    playing_card: playing_card} = game) do
    previous = player.name
    m = game.matching + 1
    game = game
           |> capture_playing_card()
           |> pick_card()
           |> next_player()
    %Game{players: [next_player|_]} = game
    EventManager.notify(game.name, {:capture, previous, playing_card, m})
    EventManager.notify(game.name, {:pick_from_deck, previous})
    EventManager.notify(game.name, {:turn, next_player.name, previous})
    if game_ends?(game) do
      EventManager.notify(game.name, {:game_over, who_wins?(game)})
      actions = [{:reply, from, :game_over},
                {:state_timeout, @max_ended_time, :terminate}]
      {:next_state, :ended, game, actions}
    else
      {:keep_state, game, [{:reply, from, :ok}]}
    end
  end

  def playing(:info, {:DOWN, _ref, :process, player_pid, _reason},
              %Game{players: players} = game) do
    players = case List.keyfind(players, player_pid, 0) do
      nil ->
        players
      {_, player_name, cards} ->
        EventManager.notify(game.name, {:disconnected, player_name})
        List.keyreplace(players, player_pid, 0, {nil, player_name, cards})
    end
    {:keep_state, %Game{game | players: players}}
  end

  def playing(:cast, :restart, _game) do
    :keep_state_and_data
  end

  ## State: ended

  def ended({:call, from}, :is_game_over?, _game) do
    {:keep_state_and_data, [{:reply, from, true}]}
  end

  def ended(:cast, :restart, game) do
    game = game
           |> Map.put(:deck, shuffle_cards())
           |> give_cards()
    {:next_state, :playing, game, [{:state_timeout, @max_game_time, :game_over}]}
  end

  def ended(:cast, _msg, _game), do: :keep_state_and_data

  def ended({:call, {player_pid, _} = from}, :get_hand,
            %Game{players: players}) do
    reply = case find_player_by_pid(players, player_pid) do
      nil ->
        :not_found
      %Player{hand_cards: cards} ->
        cards
        |> Enum.with_index(1)
        |> List.foldl(%{}, fn {v, k}, acc -> Map.put_new(acc, k, v) end)
    end
    {:keep_state_and_data, [{:reply, from, reply}]}
  end

  def ended({:call, from}, :players_num, %Game{players: players}) do
    {:keep_state_and_data, [{:reply, from, length(players)}]}
  end

  def ended({:call, from}, :deck_cards_num, %Game{deck: deck}) do
    {:keep_state_and_data, [{:reply, from, length(deck)}]}
  end

  def ended({:call, from}, :get_shown, %Game{shown: cards_shown}) do
    {:keep_state_and_data, [{:reply, from, cards_shown}]}
  end

  def ended({:call, from}, :is_my_turn?, _game) do
    {:keep_state_and_data, [{:reply, from, false}]}
  end

  def ended({:call, from}, :whose_turn_is_it?,
            %Game{players: [%Player{name: name}|_]}) do
    {:keep_state_and_data, [{:reply, from, name}]}
  end

  def ended({:call, from}, :players, %Game{players: players}) do
    players = for %Player{name: name, hand_cards: cards} <- players do
      {name, length(cards)}
    end
    {:keep_state_and_data, [{:reply, from, players}]}
  end

  def ended({:call, from}, _request, _game) do
    {:keep_state_and_data, [{:reply, from, :game_over}]}
  end

  def ended(:info, _msg, _game), do: :keep_state_and_data

  def ended(:state_timeout, :terminate, _game), do: :stop

  ## Internal functions

  defp find_player_by_name(players, name) do
    case Enum.filter(players, &(&1.name == name)) do
      [] -> nil
      [player] -> player
    end
  end

  defp find_player_by_pid(players, pid) do
    case Enum.filter(players, &(&1.pid == pid)) do
      [] -> nil
      [player] -> player
    end
  end

  defp update_player(players, changed_player) do
    for player <- players do
      if changed_player.name == player.name do
        changed_player
      else
        player
      end
    end
  end

  defp increase_number(0, number), do: number
  defp increase_number(_, 7), do: :sota
  defp increase_number(_, :sota), do: :caballo
  defp increase_number(_, :caballo), do: :rey
  defp increase_number(_, :rey), do: 1
  defp increase_number(_, i), do: i + 1

  defp give_cards(game) do
    times = @initial_cards * length(game.players)
    EventManager.notify(game.name, :dealing)
    players = Enum.map(game.players,
                       fn p -> %Player{p | hand_cards: []} end)
    game = %Game{game | players: players}
    give_card = fn(_, %Game{players: [%Player{name: player_name}|_]} = game) ->
                  EventManager.notify(game.name, {:deal, player_name})
                  game
                  |> pick_card()
                  |> next_player()
                end
    game = List.foldl(Enum.to_list(1..times), game, give_card)
           |> shown_cards()
    EventManager.notify(game.name, :dealt)
    game
  end

  defp game_ends?(%Game{deck: [], players: players}) do
    Enum.all?(players, fn(%Player{hand_cards: cards}) -> cards == [] end)
  end
  defp game_ends?(_game), do: false

  defp who_wins?(%Game{players: players}) do
    players
    |> Enum.map(fn(p) -> {length(p.captured_cards), p.name} end)
    |> Enum.sort()
    |> Enum.reverse()
    |> hd()
    |> elem(1)
  end

  defp next_player(%Game{players: [player|players]} = game) do
    %Game{game | players: players ++ [player],
                 matching: 0,
                 playing_card: nil}
  end

  defp pick_card(%Game{deck: []} = game), do: game
  defp pick_card(%Game{players: [player|players],
                       deck: [new_card|deck]} = game) do
    player = %Player{player | hand_cards: [new_card|player.hand_cards]}
    %Game{game | players: [player|players],
                 deck: deck}
  end

  defp shown_cards(game) do
    {shown, deck} = Enum.split(game.deck, @initial_cards)
    %Game{game | shown: shown, deck: deck}
  end

  defp drop_card(game) do
    %Game{game | shown: [game.playing_card|game.shown],
                 playing_card: nil}
  end

  defp capture_playing_card(%Game{players: [player|players]} = game) do
    ccards = player.captured_cards
    player = %Player{player | captured_cards: [game.playing_card|ccards]}
    %Game{game | players: [player|players], playing_card: nil}
  end

  defp shuffle_cards do
    deck = for c <- @card_kind do
      for t <- @card_number do
        {c, t}
      end
    end

    deck
    |> List.flatten()
    |> Enum.shuffle()
  end
end
