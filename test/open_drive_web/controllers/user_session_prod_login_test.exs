defmodule OpenDriveWeb.UserSessionProdLoginTest do
  use OpenDriveWeb.ConnCase

  import OpenDrive.AccountsFixtures

  alias OpenDrive.Config.Turso

  @prod_turso_host "open-drive-prod-puppe1990.aws-us-east-1.turso.io"

  test "logs the user in and redirects to /app with remember_me", %{conn: conn} do
    workspace = workspace_fixture()

    conn =
      post(conn, ~p"/users/log-in", %{
        "user" => %{
          "email" => workspace.user.email,
          "password" => valid_user_password(),
          "remember_me" => "true"
        }
      })

    assert redirected_to(conn) == ~p"/app"
    assert get_session(conn, :user_token)
    assert get_session(conn, :current_tenant_id) == workspace.tenant.id
    assert conn.resp_cookies["_open_drive_web_user_remember_me"]
  end

  test "production Turso config must not point at the panel database" do
    env = fn
      "TURSO_DATABASE_URL" -> "libsql://#{@prod_turso_host}"
      "TURSO_AUTH_TOKEN" -> "token"
      _ -> nil
    end

    config = Turso.repo_config(env)

    assert Keyword.fetch!(config, :uri) == "libsql://#{@prod_turso_host}"
    refute Keyword.fetch!(config, :uri) =~ "phoenix-paas-prod"
  end
end
