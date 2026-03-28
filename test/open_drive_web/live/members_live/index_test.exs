defmodule OpenDriveWeb.MembersLive.IndexTest do
  use OpenDriveWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders members page in pt-BR by default", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/app/members")

    assert html =~ ~s(lang="pt-BR")
    assert html =~ "Membros"
  end

  test "renders members page in english when locale=en", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/app/members?locale=en")

    assert html =~ ~s(lang="en")
    assert html =~ "Members"
    assert html =~ "Add new member"
  end
end
