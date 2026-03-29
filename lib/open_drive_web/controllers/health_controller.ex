defmodule OpenDriveWeb.HealthController do
  use OpenDriveWeb, :controller

  def show(conn, _params) do
    text(conn, "ok")
  end
end
