defmodule OpenDrive.Repo do
  @moduledoc false

  @adapter if Mix.env() == :prod,
             do: Ecto.Adapters.LibSql,
             else: Ecto.Adapters.SQLite3

  use Ecto.Repo,
    otp_app: :open_drive,
    adapter: @adapter
end
