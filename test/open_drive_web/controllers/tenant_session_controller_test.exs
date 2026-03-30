defmodule OpenDriveWeb.TenantSessionControllerTest do
  use OpenDriveWeb.ConnCase

  import OpenDrive.AccountsFixtures

  test "rejects malformed tenant ids without raising", %{conn: conn} do
    workspace = workspace_fixture()

    conn =
      conn
      |> log_in_user(workspace.user, workspace.scope)
      |> post(~p"/app/switch-tenant", %{"tenant_id" => "abc"})

    assert redirected_to(conn) == ~p"/app"
    assert is_binary(Phoenix.Flash.get(conn.assigns.flash, :error))
  end
end
