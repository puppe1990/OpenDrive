defmodule OpenDriveWeb.UploadParsers do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts) do
    parser = Keyword.get(opts, :parser, Plug.Parsers)
    parser_opts = opts |> Keyword.delete(:parser) |> parser.init()
    [parser: parser, parser_opts: parser_opts]
  end

  @impl true
  def call(conn, opts) do
    parser = Keyword.fetch!(opts, :parser)
    parser_opts = Keyword.fetch!(opts, :parser_opts)

    parser.call(conn, parser_opts)
  rescue
    exception in Plug.Parsers.ParseError ->
      if proxy_upload_tmp_space_error?(conn, exception) do
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          507,
          Jason.encode!(%{
            error:
              "The server ran out of temporary disk space while receiving this upload. Free up disk space and retry."
          })
        )
        |> halt()
      else
        reraise exception, __STACKTRACE__
      end
  end

  defp proxy_upload_tmp_space_error?(conn, exception) do
    conn.path_info == ["app", "uploads", "proxy"] and
      String.contains?(Exception.message(exception), ":enospc")
  end
end
