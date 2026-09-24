defmodule OpenDriveWeb.ScannerBlockerTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias OpenDriveWeb.ScannerBlocker

  @opts ScannerBlocker.init([])

  test "answers scanner probes with a 404" do
    for path <- [
          "/.env",
          "/.git/config",
          "/.aws/credentials",
          "/.ssh/id_rsa",
          "/wp-login.php",
          "/info.php",
          "/config.json"
        ] do
      conn = ScannerBlocker.call(conn(:get, path), @opts)

      assert conn.status == 404, "expected #{path} to be blocked"
      assert conn.halted
    end
  end

  test "lets app routes and well-known paths through" do
    for path <- ["/", "/app", "/files/123", "/.well-known/acme-challenge/token", "/users/log-in"] do
      conn = ScannerBlocker.call(conn(:get, path), @opts)

      refute conn.halted, "expected #{path} to reach the router"
      assert conn.status == nil
    end
  end
end
