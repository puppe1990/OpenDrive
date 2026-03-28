import Config

env_file = Path.expand("../.env.local", __DIR__)

if config_env() != :test and File.exists?(env_file) do
  # Load developer-local AWS/runtime variables without overriding exported shell vars.
  env_file
  |> File.read!()
  |> String.split("\n")
  |> Enum.each(fn line ->
    line = String.trim(line)

    if line != "" and not String.starts_with?(line, "#") do
      case String.split(line, "=", parts: 2) do
        [key, value] ->
          key = String.trim(key)

          value =
            value
            |> String.trim()
            |> String.trim_leading("\"")
            |> String.trim_trailing("\"")
            |> String.trim_leading("'")
            |> String.trim_trailing("'")

          if System.get_env(key) == nil do
            System.put_env(key, value)
          end

        _ ->
          :ok
      end
    end
  end)
end

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
