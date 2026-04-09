defmodule OpenDriveWeb.FolderUploadController do
  use OpenDriveWeb, :controller

  alias OpenDrive.Drive

  def create(conn, %{"folder" => attrs}) do
    case Drive.create_folder_with_available_name(conn.assigns.current_scope, attrs) do
      {:ok, folder} ->
        json(conn, %{id: folder.id, name: folder.name})

      {:error, :invalid_parent_folder} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: gettext("Target folder is invalid.")})

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: gettext("Unable to create folder.")})
    end
  end
end
