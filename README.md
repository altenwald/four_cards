# Four Cards

Four Cards Game... this is based on a very old game played in Spain "Cuatro Cartas". It's played with a Spanish deck and it's very funny when you play against other players, of course :-)

If you love this content and want we can generate more, you can support us:

[![paypal](https://www.paypalobjects.com/en_US/GB/i/btn/btn_donateCC_LG.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=RC5F8STDA6AXE)

## Getting Started

You need Erlang/OTP 29 and Elixir 1.20. Start the game server (port 4016, or the one in `PORT`):

```
mix deps.get
mix run --no-halt
```

Open <http://localhost:4016/> to play from the browser.

To play in the terminal, start the node with a name and, from another terminal, connect to it:

```
iex --sname fourcards@localhost --cookie fourcards -S mix run
iex --sname fourcards2@localhost --cookie fourcards --remsh fourcards@localhost
```

At this point both consoles are connected to the same node in different processes so, you can run `FourCardsConsole.start` in both of them and follow the instructions.

## Release

```
./build.sh
_build/prod/rel/fourcards/bin/fourcards start
```

`bin/fourcards remote` opens a shell on the running release and `:observer_cli.start()` shows what it is doing. The repository includes `dymploy.yaml` to build and deploy it with [dymploy](https://github.com/dymmer-code/dymploy).

## Development

`mix check` runs the formatter, credo, dialyzer, the tests and the dependency audit.

A sample about how to play:

[![Playing Four Cards](http://g.recordit.co/Btwzzq0SE8.gif)](http://g.recordit.co/Btwzzq0SE8.gif)

Enjoy!
