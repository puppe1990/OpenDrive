defmodule OpenDriveWeb.DirectUploadController do
  use OpenDriveWeb, :controller

  alias OpenDrive.Drive

  @token_salt "direct-upload"

  def create(conn, %{"upload" => upload_params}) do
    case Drive.prepare_direct_upload(conn.assigns.current_scope, upload_params) do
      {:ok, upload} ->
        token =
          Phoenix.Token.sign(
            OpenDriveWeb.Endpoint,
            @token_salt,
            Map.take(upload, [:key, :name, :folder_id, :content_type, :size])
          )

        json(conn, %{
          upload_url: upload.upload_url,
          upload_headers: upload.upload_headers,
          token: token
        })

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  def proxy(conn, %{"file" => %Plug.Upload{} = upload} = params) do
    attrs = %{
      "folder_id" => Map.get(params, "folder_id"),
      "name" => Map.get(params, "name")
    }

    case Drive.upload_file(conn.assigns.current_scope, attrs, %{
           path: upload.path,
           client_name: upload.filename,
           content_type: upload.content_type,
           size: upload_size(upload)
         }) do
      {:ok, file} ->
        json(conn, %{ok: true, id: file.id, name: file.name})

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  def complete(conn, %{"token" => token}) do
    with {:ok, upload} <-
           Phoenix.Token.verify(OpenDriveWeb.Endpoint, @token_salt, token, max_age: 3600),
         {:ok, _file} <- Drive.complete_direct_upload(conn.assigns.current_scope, upload) do
      json(conn, %{ok: true})
    else
      {:error, reason} ->
        render_error(conn, reason)

      _ ->
        render_error(conn, :invalid_token)
    end
  end

  defp render_error(conn, :name_conflict) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "Name already used in this folder."})
  end

  defp render_error(conn, :invalid_parent_folder) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Target folder is invalid."})
  end

  defp render_error(conn, :too_large) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Arquivo excede o limite de 2 GB."})
  end

  defp render_error(conn, :invalid_size) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Invalid file size."})
  end

  defp render_error(conn, :size_mismatch) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Uploaded object size does not match the selected file."})
  end

  defp render_error(conn, :not_found) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Uploaded object was not found in storage."})
  end

  defp render_error(conn, :invalid_token) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Upload session expired. Select the file again."})
  end

  defp render_error(conn, _reason) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: "Unable to process this upload right now."})
  end

  defp upload_size(%Plug.Upload{path: path}) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} -> size
      _ -> 0
    end
  end
end
