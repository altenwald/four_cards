# Four Cards

Four Cards Game... this is based on a very old game played in Spain "Cuatro Cartas". It's played with a Spanish deck and it's very funny when you play against other players, of course :-)

If you love this content and want we can generate more, you can support us:

[![paypal](https://www.paypalobjects.com/en_US/GB/i/btn/btn_donateCC_LG.gif)](https://www.paypal.com
/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=RC5F8STDA6AXE)

## Getting Started

It's easy, you only need to download the source code and ensure you have installed Erlang and Elixir. Then you can open two terminals and in one of them:

```
iex --sname fourcards@localhost --cookie fourcards -S mix run
```

And in the other terminal:

```
iex --sname fourcards2@localhost --cookie fourcards --remsh fourcards@localhost
```

At this point both consoles are connected to the same node in different processes so, you can run:

```
FourCards.start
```

For both terminals and following the instructions.

A sample about how to play:

[![Playing Four Cards](playing_four_cards.gif)](playing_four_cards.gif)

Enjoy!
