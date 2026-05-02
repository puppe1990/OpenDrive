defmodule OpenDriveWeb.SafeCodeReloader do
  @moduledoc false

  @behaviour Plug

  require Logger

  @impl true
  def init(opts) do
    opts
    |> Keyword.put_new(:server, Phoenix.CodeReloader.Server)
    |> Phoenix.CodeReloader.init()
  end

  @impl true
  def call(conn, opts) do
    if Process.whereis(opts[:server]) do
      Phoenix.CodeReloader.call(conn, opts)
    else
      Logger.warning(
        "Phoenix.CodeReloader.Server is not running; skipping code reload for this request"
      )

      conn
    end
  end
end
