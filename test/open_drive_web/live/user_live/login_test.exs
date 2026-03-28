defmodule OpenDriveWeb.UserLive.LoginTest do
  use OpenDriveWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the password login form", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/users/log-in")

    assert html =~ "Acesse seu workspace"
    assert html =~ "Senha"
  end

  test "reuses the selected locale inside LiveView", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/users/log-in?locale=en")

    assert html =~ ~s(lang="en")
    assert html =~ "Attempting to reconnect"
  end
end
