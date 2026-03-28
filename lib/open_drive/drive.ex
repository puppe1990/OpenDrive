defmodule OpenDrive.Drive do
  @moduledoc """
  Folder and file operations within a tenant scope.
  """

  import Ecto.Query, warn: false

  alias OpenDrive.Accounts.Scope
  alias OpenDrive.Audit
  alias OpenDrive.Drive.File, as: DriveFile
  alias OpenDrive.Drive.{FileObject, Folder, Tree}
  alias OpenDrive.Repo
  alias OpenDrive.Storage

  @max_upload_file_size 2_000_000_000
  @backend_upload_fallback_size 100_000_000

  def max_upload_file_size, do: @max_upload_file_size
  def backend_upload_fallback_size, do: @backend_upload_fallback_size

  def list_children(%Scope{} = scope, folder_id \\ nil) do
    folder_id = normalize_folder_id(folder_id)

    %{folders: list_folders(scope, folder_id), files: list_files(scope, folder_id)}
  end

  def workspace_used_size(%Scope{} = scope) do
    tenant_id = Scope.tenant_id(scope)

    DriveFile
    |> where([f], f.tenant_id == ^tenant_id and is_nil(f.deleted_at))
    |> join(:inner, [f], fo in assoc(f, :file_object))
    |> select([_f, fo], coalesce(sum(fo.size), 0))
    |> Repo.one()
  end

  def list_trash(%Scope{} = scope) do
    tenant_id = Scope.tenant_id(scope)

    %{
      folders:
        Folder
        |> where([f], f.tenant_id == ^tenant_id and not is_nil(f.deleted_at))
        |> join(:left, [f], parent in Folder, on: parent.id == f.parent_folder_id)
        |> where([_f, parent], is_nil(parent.id) or is_nil(parent.deleted_at))
        |> order_by([f], desc: f.deleted_at)
        |> Repo.all(),
      files:
        DriveFile
        |> where([f], f.tenant_id == ^tenant_id and not is_nil(f.deleted_at))
        |> join(:left, [f], folder in Folder, on: folder.id == f.folder_id)
        |> where([_f, folder], is_nil(folder.id) or is_nil(folder.deleted_at))
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
      |> normalize_name_conflict()
      |> tap_audit(scope, "folder.created", "folder")
    end
  end

  def upload_file(%Scope{} = scope, attrs, upload) do
    folder_id = attrs[:folder_id] || attrs["folder_id"]
    name = attrs[:name] || attrs["name"] || upload.client_name
    content_type = upload.content_type || "application/octet-stream"
    checksum = checksum_file(upload.path)

    with :ok <- ensure_name_available(scope, name, folder_id, :file),
         {:ok, folder_id} <- validate_parent_folder(scope, folder_id),
         key <- object_key(scope, name),
         {:ok, _object_result} <-
           Storage.put_object(key, {:file, upload.path}, content_type: content_type),
         {:ok, result} <-
           persist_upload(scope, folder_id, name, content_type, upload, key, checksum) do
      {:ok, result}
    else
      {:error, _} = error -> error
      error -> {:error, error}
    end
  end

  def prepare_direct_upload(%Scope{} = scope, attrs) do
    folder_id = attrs[:folder_id] || attrs["folder_id"]
    name = attrs[:name] || attrs["name"]
    content_type = attrs[:content_type] || attrs["content_type"] || "application/octet-stream"
    size = attrs[:size] || attrs["size"]

    with {:ok, size} <- normalize_upload_size(size),
         :ok <- validate_upload_size(size),
         :ok <- ensure_name_available(scope, name, folder_id, :file),
         {:ok, folder_id} <- validate_parent_folder(scope, folder_id),
         key <- object_key(scope, name),
         {:ok, %{url: url, headers: headers}} <-
           Storage.presigned_upload_url(key, content_type: content_type, expires_in: 3600) do
      {:ok,
       %{
         key: key,
         name: name,
         folder_id: folder_id,
         size: size,
         content_type: content_type,
         upload_url: url,
         upload_headers: headers
       }}
    else
      {:error, _} = error -> error
      error -> {:error, error}
    end
  end

  def complete_direct_upload(%Scope{} = scope, attrs) do
    folder_id = attrs[:folder_id] || attrs["folder_id"]
    name = attrs[:name] || attrs["name"]
    content_type = attrs[:content_type] || attrs["content_type"] || "application/octet-stream"
    size = attrs[:size] || attrs["size"]
    key = attrs[:key] || attrs["key"]

    with {:ok, size} <- normalize_upload_size(size),
         :ok <- validate_upload_size(size),
         :ok <- ensure_name_available(scope, name, folder_id, :file),
         {:ok, folder_id} <- validate_parent_folder(scope, folder_id),
         {:ok, object} <- Storage.head_object(key),
         :ok <- validate_uploaded_object(object, size),
         {:ok, result} <-
           persist_direct_upload(scope, folder_id, name, content_type, size, key, object) do
      {:ok, result}
    else
      {:error, _} = error -> error
      error -> {:error, error}
    end
  end

  def rename_file(%Scope{} = scope, file_id, attrs) do
    new_name = attrs[:name] || attrs["name"]

    with %DriveFile{} = file <-
           DriveFile
           |> where(
             [f],
             f.tenant_id == ^Scope.tenant_id(scope) and f.id == ^file_id and is_nil(f.deleted_at)
           )
           |> preload(:file_object)
           |> Repo.one(),
         :ok <- ensure_name_available(scope, new_name, file.folder_id, :file, file.id),
         new_key <- object_key(scope, new_name),
         {:ok, _storage_result} <- Storage.move_object(file.file_object.key, new_key),
         {:ok, renamed_file} <- persist_renamed_file(file, new_name, new_key) do
      Audit.log(scope, "file.renamed", "file", renamed_file.id, %{name: renamed_file.name})
      {:ok, renamed_file}
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def rename_folder(%Scope{} = scope, folder_id, attrs) do
    new_name = attrs[:name] || attrs["name"]

    with %Folder{} = folder <-
           Folder
           |> where(
             [f],
             f.tenant_id == ^Scope.tenant_id(scope) and f.id == ^folder_id and
               is_nil(f.deleted_at)
           )
           |> Repo.one(),
         :ok <-
           ensure_name_available(scope, new_name, folder.parent_folder_id, :folder, folder.id),
         {:ok, renamed_folder} <- persist_renamed_folder(folder, new_name) do
      Audit.log(scope, "folder.renamed", "folder", renamed_folder.id, %{name: renamed_folder.name})

      {:ok, renamed_folder}
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
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

  def bulk_download_sources(%Scope{} = scope, file_ids) do
    file_ids = normalize_file_ids(file_ids)

    files =
      DriveFile
      |> where(
        [f],
        f.tenant_id == ^Scope.tenant_id(scope) and f.id in ^file_ids and is_nil(f.deleted_at)
      )
      |> preload(:file_object)
      |> Repo.all()

    if files == [] do
      {:error, :not_found}
    else
      sources =
        files
        |> Enum.sort_by(fn file ->
          {file_position(file_ids, file.id), String.downcase(file.name)}
        end)
        |> Enum.reduce_while({:ok, []}, fn file, {:ok, acc} ->
          case Storage.presigned_download_url(file.file_object.key) do
            {:ok, url} ->
              {:cont,
               {:ok,
                [%{id: file.id, name: file.name, size: file.file_object.size, url: url} | acc]}}

            {:error, _} = error ->
              {:halt, error}
          end
        end)

      case sources do
        {:ok, items} -> {:ok, Enum.reverse(items)}
        {:error, _} = error -> error
      end
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
      folder_ids = Tree.subtree_folder_ids(scope, folder_id)

      Repo.update_all(
        from(f in Folder,
          where:
            f.tenant_id == ^Scope.tenant_id(scope) and f.id in ^folder_ids and
              is_nil(f.deleted_at)
        ),
        set: [deleted_at: timestamp]
      )

      Repo.update_all(
        from(f in DriveFile,
          where:
            f.tenant_id == ^Scope.tenant_id(scope) and f.folder_id in ^folder_ids and
              is_nil(f.deleted_at)
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
         :ok <- validate_restore_target_parent(scope, file.folder_id),
         :ok <- ensure_name_available(scope, file.name, file.folder_id, :file, file.id) do
      file
      |> DriveFile.changeset(%{deleted_at: nil})
      |> Repo.update()
      |> normalize_name_conflict()
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
         :ok <- validate_restore_target_parent(scope, folder.parent_folder_id),
         :ok <- validate_subtree_restore(scope, folder_id) do
      Repo.transaction(fn ->
        folder_ids = Tree.subtree_folder_ids(scope, folder_id)

        Repo.update_all(
          from(f in Folder,
            where:
              f.tenant_id == ^Scope.tenant_id(scope) and f.id in ^folder_ids and
                not is_nil(f.deleted_at)
          ),
          set: [deleted_at: nil]
        )

        Repo.update_all(
          from(f in DriveFile,
            where:
              f.tenant_id == ^Scope.tenant_id(scope) and f.folder_id in ^folder_ids and
                not is_nil(f.deleted_at)
          ),
          set: [deleted_at: nil]
        )

        folder
      end)
      |> normalize_transaction_result()
      |> tap_audit(scope, "folder.restored", "folder")
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def empty_trash(%Scope{} = scope) do
    tenant_id = Scope.tenant_id(scope)
    trashed_root_folder_ids = Tree.deleted_root_folder_ids(scope)
    purged_folder_ids = expand_folder_ids(scope, trashed_root_folder_ids)

    trashed_files =
      (deleted_root_files(scope) ++ Tree.files_in_folder_ids(scope, purged_folder_ids))
      |> Enum.uniq_by(& &1.id)

    case delete_trashed_objects(trashed_files) do
      :ok ->
        Repo.transaction(fn ->
          {deleted_files_count, _} =
            Repo.delete_all(
              from(f in DriveFile,
                where:
                  f.tenant_id == ^tenant_id and
                    (not is_nil(f.deleted_at) or f.folder_id in ^purged_folder_ids)
              )
            )

          file_object_ids =
            trashed_files
            |> Enum.map(& &1.file_object_id)
            |> Enum.uniq()

          {deleted_file_objects_count, _} =
            Repo.delete_all(
              from(fo in FileObject,
                where: fo.tenant_id == ^tenant_id and fo.id in ^file_object_ids
              )
            )

          {deleted_folders_count, _} =
            Repo.delete_all(
              from(f in Folder,
                where:
                  f.tenant_id == ^tenant_id and
                    (not is_nil(f.deleted_at) or f.id in ^purged_folder_ids)
              )
            )

          result = %{
            files_deleted: deleted_files_count,
            file_objects_deleted: deleted_file_objects_count,
            folders_deleted: deleted_folders_count
          }

          Audit.log(scope, "trash.emptied", "trash", tenant_id, result)

          result
        end)
        |> normalize_transaction_result()

      {:error, _} = error ->
        error
    end
  end

  defp persist_upload(scope, folder_id, name, content_type, upload, key, checksum) do
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
             |> Repo.insert()
             |> normalize_name_conflict() do
        Audit.log(scope, "file.uploaded", "file", file.id, %{name: name, size: upload.size})
        Repo.preload(file, :file_object)
      else
        {:error, reason} ->
          Storage.delete_object(key)
          Repo.rollback(reason)
      end
    end)
    |> normalize_transaction_result()
  end

  defp persist_direct_upload(scope, folder_id, name, content_type, size, key, object) do
    persisted_content_type = object[:content_type] || content_type

    Repo.transaction(fn ->
      with {:ok, file_object} <-
             %FileObject{}
             |> FileObject.changeset(%{
               tenant_id: Scope.tenant_id(scope),
               bucket: Storage.bucket(),
               key: key,
               checksum: object[:etag],
               content_type: persisted_content_type,
               size: size,
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
             |> Repo.insert()
             |> normalize_name_conflict() do
        Audit.log(scope, "file.uploaded", "file", file.id, %{name: name, size: size})
        Repo.preload(file, :file_object)
      else
        {:error, reason} ->
          Storage.delete_object(key)
          Repo.rollback(reason)
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
    case Repo.one(
           from f in Folder,
             where:
               f.id == ^folder_id and f.tenant_id == ^Scope.tenant_id(scope) and
                 is_nil(f.deleted_at)
         ) do
      %Folder{} = folder -> {:ok, folder.id}
      nil -> {:error, :invalid_parent_folder}
    end
  end

  defp validate_restore_target_parent(_scope, nil), do: :ok

  defp validate_restore_target_parent(scope, folder_id) do
    case validate_parent_folder(scope, folder_id) do
      {:ok, _folder_id} -> :ok
      {:error, :invalid_parent_folder} -> {:error, :invalid_parent_folder}
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

  defp validate_subtree_restore(scope, folder_id) do
    folder_ids = Tree.subtree_folder_ids(scope, folder_id)

    folders_to_restore =
      Folder
      |> where(
        [f],
        f.tenant_id == ^Scope.tenant_id(scope) and f.id in ^folder_ids and
          not is_nil(f.deleted_at)
      )
      |> Repo.all()

    files_to_restore = Tree.files_in_folder_ids(scope, folder_ids, deleted_only: true)

    Enum.reduce_while(folders_to_restore, :ok, fn folder, :ok ->
      case ensure_name_available(scope, folder.name, folder.parent_folder_id, :folder, folder.id) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      :ok ->
        Enum.reduce_while(files_to_restore, :ok, fn file, :ok ->
          case ensure_name_available(scope, file.name, file.folder_id, :file, file.id) do
            :ok -> {:cont, :ok}
            {:error, _} = error -> {:halt, error}
          end
        end)

      {:error, _} = error ->
        error
    end
  end

  defp object_key(scope, name) do
    stem =
      name
      |> Path.basename()
      |> Path.rootname()
      |> String.trim()
      |> String.replace(~r/[^\p{L}\p{N}\-_]+/u, "-")
      |> String.trim("-")
      |> case do
        "" -> "file"
        sanitized -> sanitized
      end

    ext = Path.extname(name)
    "tenant/#{Scope.tenant_id(scope)}/files/#{stem}-#{Ecto.UUID.generate()}#{ext}"
  end

  defp persist_renamed_file(file, new_name, new_key) do
    old_key = file.file_object.key

    case Repo.transaction(fn ->
           with {:ok, file_object} <-
                  file.file_object
                  |> FileObject.changeset(%{key: new_key})
                  |> Repo.update(),
                {:ok, renamed_file} <-
                  file
                  |> DriveFile.changeset(%{name: new_name})
                  |> Repo.update()
                  |> normalize_name_conflict() do
             %{renamed_file | file_object: file_object}
           else
             {:error, reason} -> Repo.rollback(reason)
           end
         end) do
      {:ok, renamed_file} ->
        {:ok, renamed_file}

      {:error, reason} ->
        _ = Storage.move_object(new_key, old_key)
        {:error, reason}
    end
  end

  defp persist_renamed_folder(folder, new_name) do
    folder
    |> Folder.changeset(%{name: new_name})
    |> Repo.update()
    |> normalize_name_conflict()
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

  defp normalize_file_ids(file_ids) do
    file_ids
    |> List.wrap()
    |> Enum.map(&normalize_file_id/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_file_id(file_id) when is_integer(file_id) and file_id > 0, do: file_id

  defp normalize_file_id(file_id) when is_binary(file_id) do
    case Integer.parse(file_id) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> nil
    end
  end

  defp normalize_file_id(_file_id), do: nil

  defp file_position(file_ids, file_id) do
    Enum.find_index(file_ids, &(&1 == file_id)) || length(file_ids)
  end

  defp normalize_upload_size(size) when is_integer(size) and size >= 0, do: {:ok, size}

  defp normalize_upload_size(size) when is_binary(size) do
    case Integer.parse(size) do
      {parsed, ""} when parsed >= 0 -> {:ok, parsed}
      _ -> {:error, :invalid_size}
    end
  end

  defp normalize_upload_size(_), do: {:error, :invalid_size}

  defp validate_upload_size(size) when size > 0 and size <= @max_upload_file_size, do: :ok
  defp validate_upload_size(size) when size <= 0, do: {:error, :invalid_size}
  defp validate_upload_size(_size), do: {:error, :too_large}

  defp validate_uploaded_object(%{size: size}, expected_size) when size == expected_size, do: :ok
  defp validate_uploaded_object(_object, _expected_size), do: {:error, :size_mismatch}

  defp maybe_filter_by_parent(query, nil), do: where(query, [f], is_nil(f.parent_folder_id))

  defp maybe_filter_by_parent(query, folder_id),
    do: where(query, [f], f.parent_folder_id == ^folder_id)

  defp maybe_filter_by_folder(query, nil), do: where(query, [f], is_nil(f.folder_id))
  defp maybe_filter_by_folder(query, folder_id), do: where(query, [f], f.folder_id == ^folder_id)

  defp deleted_root_files(%Scope{} = scope) do
    tenant_id = Scope.tenant_id(scope)

    DriveFile
    |> where([f], f.tenant_id == ^tenant_id and not is_nil(f.deleted_at))
    |> join(:left, [f], folder in Folder, on: folder.id == f.folder_id)
    |> where([_f, folder], is_nil(folder.id) or is_nil(folder.deleted_at))
    |> preload(:file_object)
    |> Repo.all()
  end

  defp expand_folder_ids(_scope, []), do: []

  defp expand_folder_ids(scope, folder_ids),
    do: folder_ids |> Enum.flat_map(&Tree.subtree_folder_ids(scope, &1)) |> Enum.uniq()

  defp delete_trashed_objects(files) do
    Enum.reduce_while(files, :ok, fn file, :ok ->
      case Storage.delete_object(file.file_object.key) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp tap_audit({:ok, resource}, scope, action, resource_type) do
    Audit.log(scope, action, resource_type, resource.id, %{})
    {:ok, resource}
  end

  defp tap_audit(error, _scope, _action, _resource_type), do: error

  defp normalize_name_conflict({:error, %Ecto.Changeset{} = changeset}) do
    if Keyword.has_key?(changeset.errors, :name) do
      {:error, :name_conflict}
    else
      {:error, changeset}
    end
  end

  defp normalize_name_conflict(result), do: result

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, reason}), do: {:error, reason}

  defp checksum_file(path) do
    path
    |> File.stream!([], 1_048_576)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end
end
