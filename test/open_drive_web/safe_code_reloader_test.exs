defmodule OpenDriveWeb.SafeCodeReloaderTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias OpenDriveWeb.Endpoint

  test "skips reloading when the code reloader server is unavailable" do
    opts =
      Endpoint.safe_code_reloader_init(
        server: OpenDriveWeb.MissingCodeReloaderServer,
        reloader: fn _, _ ->
          send(self(), :reloader_called)
          :ok
        end
      )

    conn =
      :get
      |> conn("/")
      |> put_private(:phoenix_endpoint, OpenDriveWeb.Endpoint)

    returned_conn = Endpoint.safe_code_reloader(conn, opts)

    refute_received :reloader_called
    assert returned_conn == conn
  end

  test "delegates to Phoenix.CodeReloader when the server is available" do
    server = start_supervised!({Agent, fn -> :ok end})
    Process.register(server, OpenDriveWeb.AvailableCodeReloaderServer)

    opts =
      Endpoint.safe_code_reloader_init(
        server: OpenDriveWeb.AvailableCodeReloaderServer,
        reloader: fn _, _ ->
          send(self(), {:reloader_called, server})
          :ok
        end
      )

    conn =
      :get
      |> conn("/")
      |> put_private(:phoenix_endpoint, OpenDriveWeb.Endpoint)

    returned_conn = Endpoint.safe_code_reloader(conn, opts)

    assert_received {:reloader_called, ^server}
    assert returned_conn == conn
  end
end
