# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :open_drive, :scopes,
  user: [
    default: true,
    module: OpenDrive.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :tenant_id,
    schema_type: :id,
    schema_table: :tenants,
    test_data_fixture: OpenDrive.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :open_drive,
  ecto_repos: [OpenDrive.Repo],
  generators: [timestamp_type: :utc_datetime]

config :open_drive, OpenDrive.Mailer, adapter: Swoosh.Adapters.Local

config :open_drive, OpenDrive.Storage,
  adapter: OpenDrive.Storage.Fake,
  bucket: "open-drive-dev"

# Configure the endpoint
config :open_drive, OpenDriveWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: OpenDriveWeb.ErrorHTML, json: OpenDriveWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: OpenDrive.PubSub,
  live_view: [signing_salt: "YL4A5GuG"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  open_drive: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  open_drive: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :ex_aws,
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role],
  region: {:system, "AWS_REGION"},
  s3: [
    scheme: "https://",
    host: System.get_env("AWS_S3_HOST"),
    port: System.get_env("AWS_S3_PORT")
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
