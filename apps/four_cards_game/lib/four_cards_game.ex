defmodule FourCardsGame do

  alias FourCardsGame.{EventManager, Game}

  @game_sup_registry FourCardsGame.Supervisor.Registry
  @game_supervisor FourCardsGame.Games

  defp via(game) do
    {:via, Registry, {@game_sup_registry, game}}
  end

  def start(game) do
    children = [
      {Game, game},
      {EventManager, game}
    ]
    opts = [strategy: :one_for_one, name: via(game)]
    args = %{
      id: __MODULE__,
      start: {Supervisor, :start_link, [children, opts]}
    }
    DynamicSupervisor.start_child(@game_supervisor, args)
  end

  defdelegate exists?(game), to: Game

  defdelegate get_event_manager_pid(name), to: EventManager, as: :get_pid

  def stop(name) do
    [{pid, nil}] = Registry.lookup(@game_supervisor, name)
    DynamicSupervisor.terminate_child(FourCardsGame.Games, pid)
  end

  defdelegate join(name, player_name), to: Game
  defdelegate deal(name), to: Game
  defdelegate get_hand(name), to: Game
  defdelegate get_players_number(name), to: Game
  defdelegate get_shown(name), to: Game
  defdelegate get_captured(name), to: Game

  defdelegate playing_card?(name), to: Game
  defdelegate play_from(name, from_num), to: Game
  defdelegate play_to(name, where, to_num), to: Game
  defdelegate pass(name), to: Game

  defdelegate is_my_turn?(name), to: Game
  defdelegate players(name), to: Game
  defdelegate whose_turn_is_it?(name), to: Game
  defdelegate deck_cards_num(name), to: Game
  defdelegate restart(name), to: Game
  defdelegate valid_name?(name, username), to: Game
  defdelegate is_game_over?(name), to: Game

  defdelegate get_pid(game), to: Game
end
