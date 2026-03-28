defmodule OpenDriveWeb.PageControllerTest do
  use OpenDriveWeb.ConnCase

  test "GET / renders the product landing page", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert html_response(conn, 200) =~ "Seu drive interno multi-tenant"
    assert html_response(conn, 200) =~ "Criar workspace"
  end
end
