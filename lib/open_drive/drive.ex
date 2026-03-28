defmodule OpenDrive.Drive do
  @moduledoc """
  Folder and file operations within a tenant scope.
  """

  import Ecto.Query, warn: false

  alias OpenDrive.Accounts.Scope
  alias OpenDrive.Audit
  alias OpenDrive.Drive.File, as: DriveFile
  alias OpenDrive.Drive.{FileObject, Folder}
  alias OpenDrive.Repo
  alias OpenDrive.Storage

  def list_children(%Scope{} = scope, folder_id \\ nil) do
    folder_id = normalize_folder_id(folder_id)

    %{folders: list_folders(scope, folder_id), files: list_files(scope, folder_id)}
  end

  def list_trash(%Scope{} = scope) do
    tenant_id = Scope.tenant_id(scope)

    %{
      folders:
        Folder
        |> where([f], f.tenant_id == ^tenant_id and not is_nil(f.deleted_at))
        |> order_by([f], desc: f.deleted_at)
        |> Repo.all(),
      files:
        DriveFile
        |> where([f], f.tenant_id == ^tenant_id and not is_nil(f.deleted_at))
        |> preload(:file_object)
        |> order_by([f], desc: f.deleted_at)
        |> Repo.all()
    }
  end

  def list_breadcrumbs(%Scope{}, nil), do: []

  def list_breadcrumbs(%Scope{} = scope, folder_id) do
    scope
    |> get_folder!(folder_id)
    |> do_breadcrumbs(scope, [])
    |> Enum.reverse()
  end

  def get_folder!(%Scope{} = scope, id) do
    Folder
    |> where([f], f.tenant_id == ^Scope.tenant_id(scope) and f.id == ^id)
    |> Repo.one!()
  end

  def create_folder(%Scope{} = scope, attrs) do
    with :ok <-
           ensure_name_available(
             scope,
             attrs[:name] || attrs["name"],
             attrs[:parent_folder_id] || attrs["parent_folder_id"],
             :folder
           ),
         {:ok, parent_folder_id} <-
           validate_parent_folder(scope, attrs[:parent_folder_id] || attrs["parent_folder_id"]) do
      %Folder{}
      |> Folder.changeset(%{
        tenant_id: Scope.tenant_id(scope),
        parent_folder_id: parent_folder_id,
        created_by_user_id: scope.user.id,
        name: attrs[:name] || attrs["name"]
      })
      |> Repo.insert()
      |> tap_audit(scope, "folder.created", "folder")
    end
  end

  def upload_file(%Scope{} = scope, attrs, upload) do
    folder_id = attrs[:folder_id] || attrs["folder_id"]
    name = attrs[:name] || attrs["name"] || upload.client_name
    content_type = upload.content_type || "application/octet-stream"

    with :ok <- ensure_name_available(scope, name, folder_id, :file),
         {:ok, folder_id} <- validate_parent_folder(scope, folder_id),
         {:ok, body} <- Elixir.File.read(upload.path),
         key <- object_key(scope, name),
         {:ok, _object_result} <- Storage.put_object(key, body, content_type: content_type),
         {:ok, result} <- persist_upload(scope, folder_id, name, content_type, upload, key, body) do
      {:ok, result}
    else
      {:error, _} = error -> error
      error -> {:error, error}
    end
  end

  def download_url(%Scope{} = scope, file_id) do
    file =
      DriveFile
      |> where(
        [f],
        f.tenant_id == ^Scope.tenant_id(scope) and f.id == ^file_id and is_nil(f.deleted_at)
      )
      |> preload(:file_object)
      |> Repo.one()

    if file do
      Storage.presigned_download_url(file.file_object.key)
    else
      {:error, :not_found}
    end
  end

  def soft_delete_node(%Scope{} = scope, {:file, file_id}) do
    timestamp = DateTime.utc_now(:second)

    DriveFile
    |> where(
      [f],
      f.tenant_id == ^Scope.tenant_id(scope) and f.id == ^file_id and is_nil(f.deleted_at)
    )
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      file ->
        file
        |> DriveFile.changeset(%{deleted_at: timestamp})
        |> Repo.update()
        |> tap_audit(scope, "file.deleted", "file")
    end
  end

  def soft_delete_node(%Scope{} = scope, {:folder, folder_id}) do
    timestamp = DateTime.utc_now(:second)

    Repo.transaction(fn ->
      folder = get_folder!(scope, folder_id)

      Repo.update!(Folder.changeset(folder, %{deleted_at: timestamp}))

      Repo.update_all(
        from(f in Folder,
          where: f.tenant_id == ^Scope.tenant_id(scope) and f.parent_folder_id == ^folder_id
        ),
        set: [deleted_at: timestamp]
      )

      Repo.update_all(
        from(f in DriveFile,
          where: f.tenant_id == ^Scope.tenant_id(scope) and f.folder_id == ^folder_id
        ),
        set: [deleted_at: timestamp]
      )

      folder
    end)
    |> normalize_transaction_result()
    |> tap_audit(scope, "folder.deleted", "folder")
  end

  def restore_node(%Scope{} = scope, {:file, file_id}) do
    with %DriveFile{} = file <-
           DriveFile
           |> where(
             [f],
             f.tenant_id == ^Scope.tenant_id(scope) and f.id == ^file_id and
               not is_nil(f.deleted_at)
           )
           |> preload(:file_object)
           |> Repo.one(),
         :ok <- ensure_name_available(scope, file.name, file.folder_id, :file, file.id) do
      file
      |> DriveFile.changeset(%{deleted_at: nil})
      |> Repo.update()
      |> tap_audit(scope, "file.restored", "file")
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def restore_node(%Scope{} = scope, {:folder, folder_id}) do
    with %Folder{} = folder <-
           Folder
           |> where(
             [f],
             f.tenant_id == ^Scope.tenant_id(scope) and f.id == ^folder_id and
               not is_nil(f.deleted_at)
           )
           |> Repo.one(),
         :ok <-
           ensure_name_available(scope, folder.name, folder.parent_folder_id, :folder, folder.id) do
      folder
      |> Folder.changeset(%{deleted_at: nil})
      |> Repo.update()
      |> tap_audit(scope, "folder.restored", "folder")
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  defp persist_upload(scope, folder_id, name, content_type, upload, key, body) do
    checksum = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

    Repo.transaction(fn ->
      with {:ok, file_object} <-
             %FileObject{}
             |> FileObject.changeset(%{
               tenant_id: Scope.tenant_id(scope),
               bucket: Storage.bucket(),
               key: key,
               checksum: checksum,
               content_type: content_type,
               size: upload.size,
               uploaded_by_user_id: scope.user.id
             })
             |> Repo.insert(),
           {:ok, file} <-
             %DriveFile{}
             |> DriveFile.changeset(%{
               tenant_id: Scope.tenant_id(scope),
               folder_id: folder_id,
               file_object_id: file_object.id,
               uploaded_by_user_id: scope.user.id,
               name: name
             })
             |> Repo.insert() do
        Audit.log(scope, "file.uploaded", "file", file.id, %{name: name, size: upload.size})
        Repo.preload(file, :file_object)
      else
        {:error, changeset} ->
          Storage.delete_object(key)
          Repo.rollback(changeset)
      end
    end)
    |> normalize_transaction_result()
  end

  defp list_folders(scope, folder_id) do
    Folder
    |> where([f], f.tenant_id == ^Scope.tenant_id(scope) and is_nil(f.deleted_at))
    |> maybe_filter_by_parent(folder_id)
    |> order_by([f], asc: f.name)
    |> Repo.all()
  end

  defp list_files(scope, folder_id) do
    DriveFile
    |> where([f], f.tenant_id == ^Scope.tenant_id(scope) and is_nil(f.deleted_at))
    |> maybe_filter_by_folder(folder_id)
    |> preload(:file_object)
    |> order_by([f], asc: f.name)
    |> Repo.all()
  end

  defp validate_parent_folder(_scope, nil), do: {:ok, nil}

  defp validate_parent_folder(scope, folder_id) do
    case Repo.get_by(Folder, id: folder_id, tenant_id: Scope.tenant_id(scope), deleted_at: nil) do
      %Folder{} = folder -> {:ok, folder.id}
      nil -> {:error, :invalid_parent_folder}
    end
  end

  defp ensure_name_available(scope, name, parent_folder_id, kind, exclude_id \\ nil) do
    parent_folder_id = normalize_folder_id(parent_folder_id)

    folder_query =
      Folder
      |> where(
        [f],
        f.tenant_id == ^Scope.tenant_id(scope) and is_nil(f.deleted_at) and f.name == ^name
      )
      |> maybe_filter_by_parent(parent_folder_id)

    file_query =
      DriveFile
      |> where(
        [f],
        f.tenant_id == ^Scope.tenant_id(scope) and is_nil(f.deleted_at) and f.name == ^name
      )
      |> maybe_filter_by_folder(parent_folder_id)

    conflict? =
      case kind do
        :folder ->
          exists_without?(folder_query, exclude_id) or Repo.exists?(file_query)

        :file ->
          Repo.exists?(folder_query) or exists_without?(file_query, exclude_id)
      end

    if conflict?, do: {:error, :name_conflict}, else: :ok
  end

  defp exists_without?(query, nil), do: Repo.exists?(query)

  defp exists_without?(query, exclude_id),
    do: Repo.exists?(from q in query, where: q.id != ^exclude_id)

  defp object_key(scope, name) do
    ext = Path.extname(name)
    "tenant/#{Scope.tenant_id(scope)}/files/#{Ecto.UUID.generate()}#{ext}"
  end

  defp do_breadcrumbs(%Folder{parent_folder_id: nil} = folder, _scope, acc), do: [folder | acc]

  defp do_breadcrumbs(%Folder{parent_folder_id: parent_id} = folder, scope, acc) do
    parent =
      Folder
      |> where([f], f.tenant_id == ^Scope.tenant_id(scope) and f.id == ^parent_id)
      |> Repo.one!()

    do_breadcrumbs(parent, scope, [folder | acc])
  end

  defp normalize_folder_id(""), do: nil
  defp normalize_folder_id(folder_id), do: folder_id

  defp maybe_filter_by_parent(query, nil), do: where(query, [f], is_nil(f.parent_folder_id))

  defp maybe_filter_by_parent(query, folder_id),
    do: where(query, [f], f.parent_folder_id == ^folder_id)

  defp maybe_filter_by_folder(query, nil), do: where(query, [f], is_nil(f.folder_id))
  defp maybe_filter_by_folder(query, folder_id), do: where(query, [f], f.folder_id == ^folder_id)

  defp tap_audit({:ok, resource}, scope, action, resource_type) do
    Audit.log(scope, action, resource_type, resource.id, %{})
    {:ok, resource}
  end

  defp tap_audit(error, _scope, _action, _resource_type), do: error

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, reason}), do: {:error, reason}
end
