defmodule OpenDriveWeb.TrashLive.IndexTest do
  use OpenDriveWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders trash page in pt-BR by default", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/app/trash")

    assert html =~ ~s(lang="pt-BR")
    assert html =~ "Lixeira"
  end

  test "renders trash page in english when locale=en", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/app/trash?locale=en")

    assert html =~ ~s(lang="en")
    assert html =~ "Trash"
    assert html =~ "Empty trash"
  end
end
