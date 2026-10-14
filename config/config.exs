import Config

config :four_cards_web, port: 4016

# Tests start a real server; keep it away from the port of a development instance.
if config_env() == :test do
  config :four_cards_web, port: 4116
  config :logger, level: :warning
end
