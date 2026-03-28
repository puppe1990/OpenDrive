defmodule OpenDriveWeb.PageControllerTest do
  use OpenDriveWeb.ConnCase

  test "GET / renders the product landing page", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert html_response(conn, 200) =~ "Seu drive interno multi-tenant"
    assert html_response(conn, 200) =~ "Criar workspace"
  end

  test "GET / persists an explicit locale override", %{conn: conn} do
    conn = get(conn, ~p"/?locale=en")

    assert html_response(conn, 200) =~ ~s(lang="en")
    assert html_response(conn, 200) =~ "Attempting to reconnect"

    conn = conn |> recycle() |> get(~p"/")

    assert html_response(conn, 200) =~ ~s(lang="en")
  end
end
