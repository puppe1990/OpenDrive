import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :open_drive, OpenDrive.Repo,
  database: Path.expand("../open_drive_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

config :open_drive, OpenDrive.Mailer, adapter: Swoosh.Adapters.Test

config :open_drive, OpenDrive.Storage,
  adapter: OpenDrive.Storage.Fake,
  bucket: "open-drive-test"

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :open_drive, OpenDriveWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Y9epsWD0Eak7zgeX8UifYQLXFm/h6jK0qtcKgRCgcOVyvhyhgDEPcfC8G0wjou1g",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
