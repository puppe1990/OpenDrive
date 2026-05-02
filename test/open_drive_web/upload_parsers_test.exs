defmodule OpenDriveWeb.UploadParsersTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias OpenDriveWeb.UploadParsers

  defmodule EnospcParser do
    def init(opts), do: opts

    def call(_conn, _opts) do
      raise Plug.Parsers.ParseError,
        exception: %CaseClauseError{term: {:error, :enospc}}
    end
  end

  defmodule GenericParseErrorParser do
    def init(opts), do: opts

    def call(_conn, _opts) do
      raise Plug.Parsers.ParseError, exception: %RuntimeError{message: "boom"}
    end
  end

  test "returns json for proxy uploads when temp storage is full" do
    conn =
      :post
      |> conn("/app/uploads/proxy")
      |> UploadParsers.call(UploadParsers.init(parser: EnospcParser, parsers: [:multipart]))

    assert conn.status == 507
    assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]

    assert Jason.decode!(conn.resp_body) == %{
             "error" =>
               "The server ran out of temporary disk space while receiving this upload. Free up disk space and retry."
           }
  end

  test "re-raises unrelated parse errors" do
    assert_raise Plug.Parsers.ParseError, fn ->
      :post
      |> conn("/app/uploads/proxy")
      |> UploadParsers.call(
        UploadParsers.init(parser: GenericParseErrorParser, parsers: [:multipart])
      )
    end
  end
end
