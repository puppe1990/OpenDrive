defmodule OpenDriveWeb.UserSessionControllerTest do
  use OpenDriveWeb.ConnCase

  import OpenDrive.AccountsFixtures

  test "logs the user in with valid credentials", %{conn: conn} do
    workspace = workspace_fixture()

    conn =
      post(conn, ~p"/users/log-in", %{
        user: %{email: workspace.user.email, password: valid_user_password()}
      })

    assert redirected_to(conn) == ~p"/app"
    assert get_session(conn, :current_tenant_id) == workspace.tenant.id
  end

  test "rejects invalid credentials", %{conn: conn} do
    workspace = workspace_fixture()

    conn =
      post(conn, ~p"/users/log-in", %{
        user: %{email: workspace.user.email, password: "wrong password"}
      })

    assert redirected_to(conn) == ~p"/users/log-in"
  end
end
