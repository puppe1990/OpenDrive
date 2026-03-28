defmodule OpenDrive.Repo do
  use Ecto.Repo,
    otp_app: :open_drive,
    adapter: Ecto.Adapters.SQLite3
end
