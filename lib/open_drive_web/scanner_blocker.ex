defmodule OpenDriveWeb.ScannerBlocker do
  @moduledoc """
  Answers vulnerability scanner probes before they reach the router or the
  request logger.

  Internet scanners constantly probe for dotfiles, PHP entrypoints and common
  configuration files. Those requests never belong to the app, so they are
  rejected early with a 404 instead of filling the logs with noise.
  """

  import Plug.Conn

  @probes ["/config.json", "/info.php"]

  def init(opts), do: opts

  def call(conn, _opts) do
    if scanner_probe?(conn.request_path) do
      conn
      |> send_resp(:not_found, "")
      |> halt()
    else
      conn
    end
  end

  defp scanner_probe?(path) do
    first_segment = path |> String.split("/", trim: true) |> List.first() || ""

    cond do
      String.starts_with?(path, "/.well-known/") -> false
      String.starts_with?(first_segment, ".") -> true
      String.ends_with?(path, ".php") -> true
      path in @probes -> true
      true -> false
    end
  end
end
