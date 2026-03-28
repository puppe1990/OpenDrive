defmodule OpenDriveWeb.FileDownloadController do
  use OpenDriveWeb, :controller

  alias OpenDrive.Drive

  def show(conn, %{"id" => id}) do
    case Drive.download_url(conn.assigns.current_scope, id) do
      {:ok, url} ->
        redirect(conn, external: url)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "File not found.")
        |> redirect(to: ~p"/app")
    end
  end
end
