defmodule OpenDriveWeb.UserLive.LoginTest do
  use OpenDriveWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the password login form", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/users/log-in")

    assert html =~ "Entrar no workspace"
    assert html =~ "Senha"
  end
end
