import Config

database_path =
  System.get_env("DATABASE_PATH") ||
    if config_env() == :prod, do: "/tmp/open_drive.db", else: nil

if database_path do
  config :open_drive, OpenDrive.Repo, database: database_path
end

storage_adapter =
  case System.get_env("OPEN_DRIVE_STORAGE_ADAPTER") do
    "s3" -> OpenDrive.Storage.S3
    _ -> OpenDrive.Storage.Fake
  end

config :open_drive, OpenDrive.Storage,
  adapter: storage_adapter,
  bucket: System.get_env("AWS_S3_BUCKET") || "open-drive-dev"
