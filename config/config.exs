# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Carga un `.env` local (no versionado) para desarrollo y tests. Ningún secreto
# vive en este repositorio: en producción las variables llegan del entorno del
# contenedor. Ver `.env.example`.
if File.exists?(".env") do
  ".env"
  |> File.read!()
  |> String.split(["\n", "\r\n"], trim: true)
  |> Enum.reject(&(String.starts_with?(String.trim(&1), "#") or String.trim(&1) == ""))
  |> Enum.each(fn line ->
    case String.split(line, "=", parts: 2) do
      [key, value] -> System.put_env(String.trim(key), String.trim(value))
      _ -> :ok
    end
  end)
end

config :nexo,
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :nexo, NexoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: NexoWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Nexo.PubSub,
  live_view: [signing_salt: "WvrRrwF6"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
