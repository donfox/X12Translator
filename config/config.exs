# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :x12_bridge,
  ecto_repos: [X12Bridge.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :x12_bridge, X12BridgeWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: X12BridgeWeb.ErrorHTML, json: X12BridgeWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: X12Bridge.PubSub,
  live_view: [signing_salt: "FEk+XFig"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  x12_bridge: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  x12_bridge: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure custom MIME types for X12 EDI files
config :mime, :types, %{
  "application/x12" => ["x12"],
  "application/edi" => ["edi"],
  "text/plain" => ["txt"]
}

# Configure batch retention policy
config :x12_bridge, :batch_max_concurrency, System.schedulers_online()

# Configure hot folder processing
config :x12_bridge, :batch_hot_folder,
  input_dir: "priv/batch_processing/input",
  output_dir: "priv/batch_processing/output",
  allowed_extensions: [".x12", ".edi", ".txt"]

config :x12_bridge, :batch_retention,
  # Keep only the 50 most recent batches in development
  max_batches: 50

# Configure remote batch fetcher
config :x12_bridge, :remote_fetcher,
  download_timeout_ms: 60_000,
  max_file_size_bytes: 100_000_000,
  allowed_extensions: [".x12", ".edi", ".txt"]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
