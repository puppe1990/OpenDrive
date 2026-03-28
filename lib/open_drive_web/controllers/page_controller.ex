defmodule OpenDriveWeb.PageController do
  use OpenDriveWeb, :controller

  def home(conn, _params) do
    if conn.assigns[:current_scope] && conn.assigns.current_scope.user do
      redirect(conn, to: ~p"/app")
    else
      render(conn, :home)
    end
  end
end
