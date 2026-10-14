import Config

# The port can be changed without rebuilding the release.
if port = System.get_env("PORT") do
  config :four_cards_web, port: String.to_integer(port)
end
