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

  test "redirects stale sessions when updating password", %{conn: conn} do
    workspace = workspace_fixture()

    conn =
      conn
      |> log_in_user(
        workspace.user,
        workspace.scope,
        token_authenticated_at: DateTime.add(DateTime.utc_now(), -30, :minute)
      )
      |> post(~p"/users/update-password", %{
        user: %{
          email: workspace.user.email,
          password: "new secure password 123",
          password_confirmation: "new secure password 123"
        }
      })

    assert redirected_to(conn) == ~p"/users/log-in"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "You must re-authenticate to update your password."
  end
end
