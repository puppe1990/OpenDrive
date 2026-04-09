defmodule OpenDriveWeb.DirectUploadController do
  use OpenDriveWeb, :controller

  alias OpenDrive.Drive

  @token_salt "direct-upload"
  @backend_upload_fallback_size Drive.backend_upload_fallback_size()

  def create(conn, %{"upload" => upload_params}) do
    case Drive.prepare_direct_upload(conn.assigns.current_scope, upload_params) do
      {:ok, upload} ->
        token =
          Phoenix.Token.sign(
            OpenDriveWeb.Endpoint,
            @token_salt,
            Map.merge(
              Map.take(upload, [:key, :name, :folder_id, :content_type, :size]),
              %{
                tenant_id: conn.assigns.current_scope.tenant.id,
                prepared_by_user_id: conn.assigns.current_scope.user.id
              }
            )
          )

        json(conn, %{
          name: upload.name,
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

    case upload_size(upload) do
      size when size > @backend_upload_fallback_size ->
        render_error(conn, :proxy_too_large)

      size ->
        case Drive.upload_file(conn.assigns.current_scope, attrs, %{
               path: upload.path,
               client_name: upload.filename,
               content_type: upload.content_type,
               size: size
             }) do
          {:ok, file} ->
            json(conn, %{ok: true, id: file.id, name: file.name})

          {:error, reason} ->
            render_error(conn, reason)
        end
    end
  end

  def complete(conn, %{"token" => token}) do
    with {:ok, upload} <-
           Phoenix.Token.verify(OpenDriveWeb.Endpoint, @token_salt, token, max_age: 3600),
         :ok <- validate_upload_context(conn.assigns.current_scope, upload),
         {:ok, file} <- Drive.complete_direct_upload(conn.assigns.current_scope, upload) do
      json(conn, %{ok: true, name: file.name})
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
    |> json(%{error: gettext("Name already used in this folder.")})
  end

  defp render_error(conn, :invalid_parent_folder) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: gettext("Target folder is invalid.")})
  end

  defp render_error(conn, :too_large) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: gettext("File exceeds the 2 GB limit.")})
  end

  defp render_error(conn, :proxy_too_large) do
    conn
    |> put_status(413)
    |> json(%{
      error:
        gettext("Browser fallback accepts files up to %{size}. Retry direct upload instead.",
          size: format_bytes(@backend_upload_fallback_size)
        )
    })
  end

  defp render_error(conn, :invalid_size) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: gettext("Invalid file size.")})
  end

  defp render_error(conn, :size_mismatch) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: gettext("Uploaded object size does not match the selected file.")})
  end

  defp render_error(conn, :content_type_mismatch) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: gettext("Uploaded object type does not match the selected file.")})
  end

  defp render_error(conn, :not_found) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: gettext("Uploaded object was not found in storage.")})
  end

  defp render_error(conn, :invalid_token) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: gettext("Upload session expired. Select the file again.")})
  end

  defp render_error(conn, :storage_unavailable) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{
      error:
        gettext(
          "The storage service did not respond in time. Retry the upload in a few seconds."
        )
    })
  end

  defp render_error(conn, :forbidden) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      error: gettext("Upload session belongs to a different workspace or user. Start again.")
    })
  end

  defp render_error(conn, _reason) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: gettext("Unable to process this upload right now.")})
  end

  defp upload_size(%Plug.Upload{path: path}) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} -> size
      _ -> 0
    end
  end

  defp validate_upload_context(scope, %{
         tenant_id: tenant_id,
         prepared_by_user_id: prepared_by_user_id
       }) do
    if scope.tenant.id == tenant_id and scope.user.id == prepared_by_user_id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp validate_upload_context(_scope, _upload), do: {:error, :invalid_token}

  defp format_bytes(size) when size >= 1_000_000 do
    megabytes = Float.round(size / 1_000_000, 1)
    "#{megabytes} MB"
  end

  defp format_bytes(size), do: "#{size} B"
end
