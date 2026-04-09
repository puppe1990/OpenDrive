defmodule OpenDrive.DriveTest do
  use OpenDrive.DataCase

  alias OpenDrive.Drive
  alias OpenDrive.Drive.File, as: DriveFile
  alias OpenDrive.Drive.{FileObject, Folder}
  alias OpenDrive.Repo

  import OpenDrive.AccountsFixtures

  defmodule FailingStorage do
    @behaviour OpenDrive.Storage
    def put_object(_key, _body, _opts), do: {:error, :boom}
    def presigned_upload_url(_key, _opts), do: {:error, :boom}
    def head_object(_key), do: {:error, :boom}
    def delete_object(_key), do: :ok
    def move_object(_source_key, _destination_key, _opts), do: {:error, :boom}
    def presigned_download_url(_key, _opts), do: {:error, :boom}
  end

  defmodule MismatchedHeadStorage do
    @behaviour OpenDrive.Storage
    alias OpenDrive.Storage.Fake

    def put_object(key, source, opts), do: Fake.put_object(key, source, opts)

    def presigned_upload_url(key, opts), do: Fake.presigned_upload_url(key, opts)

    def head_object(key) do
      case Fake.head_object(key) do
        {:ok, object} -> {:ok, %{object | content_type: "application/pdf"}}
        error -> error
      end
    end

    def delete_object(key), do: Fake.delete_object(key)

    def move_object(source_key, destination_key, opts),
      do: Fake.move_object(source_key, destination_key, opts)

    def presigned_download_url(key, opts), do: Fake.presigned_download_url(key, opts)
  end

  defmodule DeleteFailingStorage do
    @behaviour OpenDrive.Storage
    alias OpenDrive.Storage.Fake

    def put_object(key, source, opts), do: Fake.put_object(key, source, opts)

    def presigned_upload_url(key, opts), do: Fake.presigned_upload_url(key, opts)

    def head_object(key), do: Fake.head_object(key)
    def delete_object(_key), do: {:error, :boom}

    def move_object(source_key, destination_key, opts),
      do: Fake.move_object(source_key, destination_key, opts)

    def presigned_download_url(key, opts), do: Fake.presigned_download_url(key, opts)
  end

  defmodule ExitingStorage do
    @behaviour OpenDrive.Storage

    def put_object(_key, _source, _opts), do: exit(:timeout)
    def presigned_upload_url(_key, _opts), do: {:error, :boom}
    def head_object(_key), do: {:error, :boom}
    def delete_object(_key), do: :ok
    def move_object(_source_key, _destination_key, _opts), do: {:error, :boom}
    def presigned_download_url(_key, _opts), do: {:error, :boom}
  end

  test "users do not see data from another tenant" do
    workspace_a = workspace_fixture()
    workspace_b = workspace_fixture()

    {:ok, folder} = Drive.create_folder(workspace_a.scope, %{name: "Finance"})

    assert [listed_folder] = Drive.list_children(workspace_a.scope).folders
    assert listed_folder.id == folder.id
    assert [] = Drive.list_children(workspace_b.scope).folders
  end

  test "create_folder/2 enforces unique names within the same directory" do
    workspace = workspace_fixture()

    assert {:ok, _folder} = Drive.create_folder(workspace.scope, %{name: "Contracts"})
    assert {:error, :name_conflict} = Drive.create_folder(workspace.scope, %{name: "Contracts"})
  end

  test "create_folder_with_available_name/2 suffixes conflicting folders in the same directory" do
    workspace = workspace_fixture()

    assert {:ok, first} =
             Drive.create_folder_with_available_name(workspace.scope, %{name: "Photos"})

    assert {:ok, second} =
             Drive.create_folder_with_available_name(workspace.scope, %{name: "Photos"})

    assert first.name == "Photos"
    assert second.name == "Photos (2)"
  end

  test "upload_file/3 persists metadata and object references" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-upload.txt")
    Elixir.File.write!(path, "hello")

    assert {:ok, file} =
             Drive.upload_file(workspace.scope, %{}, %{
               path: path,
               client_name: "hello.txt",
               content_type: "text/plain",
               size: 5
             })

    assert file.file_object.bucket == OpenDrive.Storage.bucket()
    assert Repo.aggregate(FileObject, :count) == 1
  end

  test "upload_file/3 accepts a custom name override" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-custom-name.txt")
    Elixir.File.write!(path, "hello")

    assert {:ok, file} =
             Drive.upload_file(workspace.scope, %{name: "renamed.txt"}, %{
               path: path,
               client_name: "hello.txt",
               content_type: "text/plain",
               size: 5
             })

    assert file.name == "renamed.txt"
  end

  test "upload_file/3 auto-renames duplicates inside the same folder" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-duplicate-upload.txt")
    File.write!(path, "hello")

    assert {:ok, first_file} =
             Drive.upload_file(workspace.scope, %{}, %{
               path: path,
               client_name: "report.txt",
               content_type: "text/plain",
               size: 5
             })

    assert {:ok, second_file} =
             Drive.upload_file(workspace.scope, %{}, %{
               path: path,
               client_name: "report.txt",
               content_type: "text/plain",
               size: 5
             })

    assert first_file.name == "report.txt"
    assert second_file.name == "report (2).txt"
  end

  test "prepare_direct_upload/2 returns a storage target without reading the file" do
    workspace = workspace_fixture()

    assert {:ok, upload} =
             Drive.prepare_direct_upload(workspace.scope, %{
               "name" => "video.mp4",
               "content_type" => "video/mp4",
               "size" => "1024"
             })

    assert upload.name == "video.mp4"
    assert upload.size == 1024
    assert upload.content_type == "video/mp4"
    assert is_binary(upload.key)
    assert is_binary(upload.upload_url)
    assert is_map(upload.upload_headers)
  end

  test "prepare_direct_upload/2 reserves an alternative name for duplicates" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-duplicate-direct.txt")
    File.write!(path, "hello")

    assert {:ok, _file} =
             Drive.upload_file(workspace.scope, %{}, %{
               path: path,
               client_name: "movie.mp4",
               content_type: "video/mp4",
               size: 5
             })

    assert {:ok, upload} =
             Drive.prepare_direct_upload(workspace.scope, %{
               "name" => "movie.mp4",
               "content_type" => "video/mp4",
               "size" => "5"
             })

    assert upload.name == "movie (2).mp4"
  end

  test "complete_direct_upload/2 auto-renames when a conflict appears after preparation" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-direct-race.txt")
    File.write!(path, "hello")

    {:ok, upload} =
      Drive.prepare_direct_upload(workspace.scope, %{
        "name" => "movie.mp4",
        "content_type" => "video/mp4",
        "size" => "5"
      })

    assert {:ok, _file} =
             Drive.upload_file(workspace.scope, %{}, %{
               path: path,
               client_name: "movie.mp4",
               content_type: "video/mp4",
               size: 5
             })

    assert {:ok, _} = OpenDrive.Storage.put_object(upload.key, "hello", content_type: "video/mp4")

    assert {:ok, file} =
             Drive.complete_direct_upload(workspace.scope, %{
               "folder_id" => upload.folder_id,
               "name" => upload.name,
               "content_type" => upload.content_type,
               "size" => upload.size,
               "key" => upload.key
             })

    assert file.name == "movie (2).mp4"
  end

  test "complete_direct_upload/2 persists metadata after the object exists in storage" do
    workspace = workspace_fixture()

    {:ok, upload} =
      Drive.prepare_direct_upload(workspace.scope, %{
        "name" => "movie.mp4",
        "content_type" => "video/mp4",
        "size" => "5"
      })

    assert {:ok, _} = OpenDrive.Storage.put_object(upload.key, "hello", content_type: "video/mp4")

    assert {:ok, file} =
             Drive.complete_direct_upload(workspace.scope, %{
               "folder_id" => upload.folder_id,
               "name" => upload.name,
               "content_type" => upload.content_type,
               "size" => upload.size,
               "key" => upload.key
             })

    assert file.name == "movie.mp4"
    assert file.file_object.size == 5
    assert file.file_object.content_type == "video/mp4"
  end

  test "complete_direct_upload/2 rejects mismatched content types" do
    original = Application.get_env(:open_drive, OpenDrive.Storage)

    Application.put_env(
      :open_drive,
      OpenDrive.Storage,
      Keyword.put(original, :adapter, MismatchedHeadStorage)
    )

    on_exit(fn -> Application.put_env(:open_drive, OpenDrive.Storage, original) end)

    workspace = workspace_fixture()

    {:ok, upload} =
      Drive.prepare_direct_upload(workspace.scope, %{
        "name" => "movie.mp4",
        "content_type" => "video/mp4",
        "size" => "5"
      })

    assert {:ok, _} = OpenDrive.Storage.put_object(upload.key, "hello", content_type: "video/mp4")

    assert {:error, :content_type_mismatch} =
             Drive.complete_direct_upload(workspace.scope, %{
               "folder_id" => upload.folder_id,
               "name" => upload.name,
               "content_type" => upload.content_type,
               "size" => upload.size,
               "key" => upload.key
             })
  end

  test "rename_file/3 updates the database name and moves the stored object" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-rename-source.txt")
    Elixir.File.write!(path, "hello")

    assert {:ok, file} =
             Drive.upload_file(workspace.scope, %{}, %{
               path: path,
               client_name: "draft.txt",
               content_type: "text/plain",
               size: 5
             })

    old_key = file.file_object.key

    old_path =
      Path.join([System.tmp_dir!(), "open_drive_storage", OpenDrive.Storage.bucket(), old_key])

    assert File.exists?(old_path)

    assert {:ok, renamed_file} = Drive.rename_file(workspace.scope, file.id, %{name: "final.txt"})

    refute renamed_file.file_object.key == old_key
    assert renamed_file.name == "final.txt"
    assert String.contains?(renamed_file.file_object.key, "final")

    new_path =
      Path.join([
        System.tmp_dir!(),
        "open_drive_storage",
        OpenDrive.Storage.bucket(),
        renamed_file.file_object.key
      ])

    refute File.exists?(old_path)
    assert File.exists?(new_path)
  end

  test "rename_folder/3 updates the folder name within the same directory" do
    workspace = workspace_fixture()
    {:ok, folder} = Drive.create_folder(workspace.scope, %{name: "Drafts"})

    assert {:ok, renamed_folder} =
             Drive.rename_folder(workspace.scope, folder.id, %{name: "Approved"})

    assert renamed_folder.name == "Approved"
    assert [%{id: listed_id, name: "Approved"}] = Drive.list_children(workspace.scope).folders
    assert listed_id == folder.id
  end

  test "rename_folder/3 enforces unique names within the same directory" do
    workspace = workspace_fixture()
    {:ok, _folder} = Drive.create_folder(workspace.scope, %{name: "Finance"})
    {:ok, folder} = Drive.create_folder(workspace.scope, %{name: "Legal"})

    assert {:error, :name_conflict} =
             Drive.rename_folder(workspace.scope, folder.id, %{name: "Finance"})
  end

  test "upload_file/3 persists files inside an existing folder" do
    workspace = workspace_fixture()
    {:ok, folder} = Drive.create_folder(workspace.scope, %{name: "Fotos"})
    path = Path.join(System.tmp_dir!(), "open_drive-upload-folder.txt")
    Elixir.File.write!(path, "hello")

    assert {:ok, file} =
             Drive.upload_file(workspace.scope, %{folder_id: folder.id}, %{
               path: path,
               client_name: "inside-folder.txt",
               content_type: "text/plain",
               size: 5
             })

    assert file.folder_id == folder.id
    assert [%{id: uploaded_id}] = Drive.list_children(workspace.scope, folder.id).files
    assert uploaded_id == file.id
  end

  test "upload_file/3 does not leave orphan metadata when storage fails" do
    original = Application.get_env(:open_drive, OpenDrive.Storage)

    Application.put_env(
      :open_drive,
      OpenDrive.Storage,
      Keyword.put(original, :adapter, FailingStorage)
    )

    on_exit(fn -> Application.put_env(:open_drive, OpenDrive.Storage, original) end)

    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-upload-fail.txt")
    Elixir.File.write!(path, "hello")

    assert {:error, :boom} =
             Drive.upload_file(workspace.scope, %{}, %{
               path: path,
               client_name: "hello.txt",
               content_type: "text/plain",
               size: 5
             })

    assert Repo.aggregate(DriveFile, :count) == 0
    assert Repo.aggregate(FileObject, :count) == 0
  end

  test "upload_file/3 returns an error when the storage adapter exits" do
    original = Application.get_env(:open_drive, OpenDrive.Storage)

    Application.put_env(
      :open_drive,
      OpenDrive.Storage,
      Keyword.put(original, :adapter, ExitingStorage)
    )

    on_exit(fn -> Application.put_env(:open_drive, OpenDrive.Storage, original) end)

    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-upload-exit.txt")
    File.write!(path, "hello")

    assert {:error, :storage_unavailable} =
             Drive.upload_file(workspace.scope, %{}, %{
               path: path,
               client_name: "hello.txt",
               content_type: "text/plain",
               size: 5
             })

    assert Repo.aggregate(DriveFile, :count) == 0
    assert Repo.aggregate(FileObject, :count) == 0
  end

  test "soft delete moves file out of listing and restore fails on name conflict" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-restore.txt")
    Elixir.File.write!(path, "hello")

    {:ok, file} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "doc.txt",
        content_type: "text/plain",
        size: 5
      })

    assert {:ok, _} = Drive.soft_delete_node(workspace.scope, {:file, file.id})
    assert [] = Drive.list_children(workspace.scope).files
    assert [trashed] = Drive.list_trash(workspace.scope).files
    assert trashed.id == file.id

    {:ok, _replacement} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "doc.txt",
        content_type: "text/plain",
        size: 5
      })

    assert {:error, :name_conflict} = Drive.restore_node(workspace.scope, {:file, file.id})
  end

  test "soft deleting a folder marks the entire subtree and restoring it restores descendants" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-tree-restore.txt")
    File.write!(path, "hello")

    {:ok, root} = Drive.create_folder(workspace.scope, %{name: "Projects"})

    {:ok, child} =
      Drive.create_folder(workspace.scope, %{name: "2026", parent_folder_id: root.id})

    {:ok, nested_file} =
      Drive.upload_file(workspace.scope, %{folder_id: child.id}, %{
        path: path,
        client_name: "plan.txt",
        content_type: "text/plain",
        size: 5
      })

    assert {:ok, _} = Drive.soft_delete_node(workspace.scope, {:folder, root.id})
    assert [] = Drive.list_children(workspace.scope).folders
    assert [%{id: root_id}] = Drive.list_trash(workspace.scope).folders
    assert root_id == root.id
    assert [] = Drive.list_trash(workspace.scope).files

    assert {:ok, _} = Drive.restore_node(workspace.scope, {:folder, root.id})
    assert [%{id: restored_root_id}] = Drive.list_children(workspace.scope).folders
    assert restored_root_id == root.id
    assert [%{id: restored_child_id}] = Drive.list_children(workspace.scope, root.id).folders
    assert restored_child_id == child.id
    assert [%{id: restored_file_id}] = Drive.list_children(workspace.scope, child.id).files
    assert restored_file_id == nested_file.id
  end

  test "restoring a folder fails atomically when a descendant name conflicts" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-tree-conflict.txt")
    File.write!(path, "hello")

    {:ok, root} = Drive.create_folder(workspace.scope, %{name: "Projects"})

    {:ok, child} =
      Drive.create_folder(workspace.scope, %{name: "2026", parent_folder_id: root.id})

    {:ok, file} =
      Drive.upload_file(workspace.scope, %{folder_id: child.id}, %{
        path: path,
        client_name: "plan.txt",
        content_type: "text/plain",
        size: 5
      })

    assert {:ok, _} = Drive.soft_delete_node(workspace.scope, {:folder, root.id})
    assert {:ok, _} = Drive.create_folder(workspace.scope, %{name: "Projects"})

    {:ok, replacement_root} =
      Drive.list_children(workspace.scope).folders |> List.first() |> then(&{:ok, &1})

    {:ok, replacement_child} =
      Drive.create_folder(workspace.scope, %{name: "2026", parent_folder_id: replacement_root.id})

    assert {:ok, _replacement_file} =
             Drive.upload_file(workspace.scope, %{folder_id: replacement_child.id}, %{
               path: path,
               client_name: "plan.txt",
               content_type: "text/plain",
               size: 5
             })

    assert {:error, :name_conflict} = Drive.restore_node(workspace.scope, {:folder, root.id})
    assert [%{id: trashed_root_id}] = Drive.list_trash(workspace.scope).folders
    assert trashed_root_id == root.id
    assert [] = Drive.list_children(workspace.scope, child.id).files
    assert Repo.get!(DriveFile, file.id).deleted_at
  end

  test "empty_trash removes files from nested trashed folders" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-empty-trash-tree.txt")
    File.write!(path, "hello")

    {:ok, root} = Drive.create_folder(workspace.scope, %{name: "Archive"})

    {:ok, child} =
      Drive.create_folder(workspace.scope, %{name: "Invoices", parent_folder_id: root.id})

    {:ok, file} =
      Drive.upload_file(workspace.scope, %{folder_id: child.id}, %{
        path: path,
        client_name: "invoice.txt",
        content_type: "text/plain",
        size: 5
      })

    storage_path =
      Path.join([
        System.tmp_dir!(),
        "open_drive_storage",
        OpenDrive.Storage.bucket(),
        file.file_object.key
      ])

    assert File.exists?(storage_path)
    assert {:ok, _} = Drive.soft_delete_node(workspace.scope, {:folder, root.id})
    assert {:ok, result} = Drive.empty_trash(workspace.scope)
    assert result.files_deleted == 1
    assert result.folders_deleted == 2
    refute File.exists?(storage_path)
    assert Repo.aggregate(DriveFile, :count) == 0
    assert Repo.aggregate(Folder, :count) == 0
  end

  test "database constraints reject duplicate active folder names in the same directory" do
    workspace = workspace_fixture()

    assert {:ok, _} = Drive.create_folder(workspace.scope, %{name: "Contracts"})

    assert {:error, changeset} =
             %Folder{}
             |> Folder.changeset(%{
               tenant_id: workspace.tenant.id,
               name: "Contracts"
             })
             |> Repo.insert()

    assert "has already been taken" in errors_on(changeset).name
  end

  test "empty_trash/1 permanently deletes trashed files from storage and keeps other tenants isolated" do
    workspace = workspace_fixture()
    other_workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-empty-trash.txt")
    Elixir.File.write!(path, "hello")

    {:ok, file} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "doc.txt",
        content_type: "text/plain",
        size: 5
      })

    {:ok, other_file} =
      Drive.upload_file(other_workspace.scope, %{}, %{
        path: path,
        client_name: "other.txt",
        content_type: "text/plain",
        size: 5
      })

    {:ok, folder} = Drive.create_folder(workspace.scope, %{name: "Temporary"})

    storage_path =
      Path.join([
        System.tmp_dir!(),
        "open_drive_storage",
        OpenDrive.Storage.bucket(),
        file.file_object.key
      ])

    other_storage_path =
      Path.join([
        System.tmp_dir!(),
        "open_drive_storage",
        OpenDrive.Storage.bucket(),
        other_file.file_object.key
      ])

    assert File.exists?(storage_path)
    assert File.exists?(other_storage_path)

    assert {:ok, _} = Drive.soft_delete_node(workspace.scope, {:file, file.id})
    assert {:ok, _} = Drive.soft_delete_node(workspace.scope, {:folder, folder.id})

    assert {:ok, result} = Drive.empty_trash(workspace.scope)
    assert result.files_deleted == 1
    assert result.folders_deleted == 1
    assert result.file_objects_deleted == 1

    refute File.exists?(storage_path)
    assert File.exists?(other_storage_path)

    assert [] = Drive.list_trash(workspace.scope).files
    assert [] = Drive.list_trash(workspace.scope).folders
    assert [%{id: other_file_id}] = Drive.list_children(other_workspace.scope).files
    assert other_file_id == other_file.id

    assert Repo.aggregate(DriveFile, :count) == 1
    assert Repo.aggregate(FileObject, :count) == 1
  end

  test "empty_trash/1 removes database references even when storage cleanup fails" do
    original = Application.get_env(:open_drive, OpenDrive.Storage)

    Application.put_env(
      :open_drive,
      OpenDrive.Storage,
      Keyword.put(original, :adapter, DeleteFailingStorage)
    )

    on_exit(fn -> Application.put_env(:open_drive, OpenDrive.Storage, original) end)

    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-empty-trash-delete-fail.txt")
    File.write!(path, "hello")

    {:ok, file} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "doc.txt",
        content_type: "text/plain",
        size: 5
      })

    assert {:ok, _} = Drive.soft_delete_node(workspace.scope, {:file, file.id})
    assert {:ok, result} = Drive.empty_trash(workspace.scope)
    assert result.files_deleted == 1
    assert result.file_objects_deleted == 1
    assert Repo.aggregate(DriveFile, :count) == 0
    assert Repo.aggregate(FileObject, :count) == 0
  end

  test "upload_file/3 accepts zero-size files (empty files allowed)" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-zero-size.txt")
    File.write!(path, "")

    assert {:ok, file} =
             Drive.upload_file(workspace.scope, %{}, %{
               path: path,
               client_name: "empty.txt",
               content_type: "text/plain",
               size: 0
             })

    assert file.file_object.size == 0
  end

  test "upload_file/3 accepts large files (validation delegated to upload method)" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-huge.txt")
    File.write!(path, "content")

    assert {:ok, _file} =
             Drive.upload_file(workspace.scope, %{}, %{
               path: path,
               client_name: "huge.txt",
               content_type: "text/plain",
               size: 2_000_000_001
             })
  end

  test "prepare_direct_upload/2 rejects zero-size" do
    workspace = workspace_fixture()

    assert {:error, :invalid_size} =
             Drive.prepare_direct_upload(workspace.scope, %{
               "name" => "video.mp4",
               "content_type" => "video/mp4",
               "size" => "0"
             })
  end

  test "prepare_direct_upload/2 rejects negative size" do
    workspace = workspace_fixture()

    assert {:error, :invalid_size} =
             Drive.prepare_direct_upload(workspace.scope, %{
               "name" => "video.mp4",
               "content_type" => "video/mp4",
               "size" => "-1"
             })
  end

  test "prepare_direct_upload/2 rejects non-numeric size" do
    workspace = workspace_fixture()

    assert {:error, :invalid_size} =
             Drive.prepare_direct_upload(workspace.scope, %{
               "name" => "video.mp4",
               "content_type" => "video/mp4",
               "size" => "abc"
             })
  end

  test "prepare_direct_upload/2 rejects size exceeding max" do
    workspace = workspace_fixture()

    assert {:error, :too_large} =
             Drive.prepare_direct_upload(workspace.scope, %{
               "name" => "video.mp4",
               "content_type" => "video/mp4",
               "size" => "2000000001"
             })
  end

  test "upload_file/3 accepts files over max size (size validation only in direct upload)" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-huge.txt")
    File.write!(path, "content")

    assert {:ok, _file} =
             Drive.upload_file(workspace.scope, %{}, %{
               path: path,
               client_name: "huge.txt",
               content_type: "text/plain",
               size: 2_000_000_001
             })
  end

  test "create_folder/2 rejects empty name" do
    workspace = workspace_fixture()

    assert {:error, :name_conflict} = Drive.create_folder(workspace.scope, %{name: ""})
  end

  test "create_folder/2 rejects names exceeding max length" do
    workspace = workspace_fixture()
    long_name = String.duplicate("a", 121)

    assert {:error, :name_conflict} = Drive.create_folder(workspace.scope, %{name: long_name})
  end

  test "rename_file/3 rejects empty name" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-rename-empty.txt")
    File.write!(path, "hello")

    {:ok, file} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "doc.txt",
        content_type: "text/plain",
        size: 5
      })

    assert {:error, :name_conflict} = Drive.rename_file(workspace.scope, file.id, %{name: ""})
  end

  test "rename_folder/3 rejects empty name" do
    workspace = workspace_fixture()
    {:ok, folder} = Drive.create_folder(workspace.scope, %{name: "Drafts"})

    assert {:error, :name_conflict} = Drive.rename_folder(workspace.scope, folder.id, %{name: ""})
  end

  test "download_url/2 returns error for non-existent file" do
    workspace = workspace_fixture()

    assert {:error, :not_found} = Drive.download_url(workspace.scope, 99_999)
  end

  test "download_url/2 returns error for trashed file" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-download-trashed.txt")
    File.write!(path, "hello")

    {:ok, file} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "trashed.txt",
        content_type: "text/plain",
        size: 5
      })

    assert {:ok, _} = Drive.soft_delete_node(workspace.scope, {:file, file.id})

    assert {:error, :not_found} = Drive.download_url(workspace.scope, file.id)
  end

  test "soft_delete_node/2 returns error for already trashed file" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-double-delete.txt")
    File.write!(path, "hello")

    {:ok, file} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "doc.txt",
        content_type: "text/plain",
        size: 5
      })

    assert {:ok, _} = Drive.soft_delete_node(workspace.scope, {:file, file.id})
    assert {:error, :not_found} = Drive.soft_delete_node(workspace.scope, {:file, file.id})
  end

  test "restore_node/2 returns error for already active file" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-double-restore.txt")
    File.write!(path, "hello")

    {:ok, file} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "doc.txt",
        content_type: "text/plain",
        size: 5
      })

    assert {:error, :not_found} = Drive.restore_node(workspace.scope, {:file, file.id})
  end

  test "create_folder/2 allows unicode filenames" do
    workspace = workspace_fixture()

    assert {:ok, folder} = Drive.create_folder(workspace.scope, %{name: "文档"})
    assert folder.name == "文档"

    assert {:ok, folder2} = Drive.create_folder(workspace.scope, %{name: "📁文件夹"})
    assert folder2.name == "📁文件夹"
  end

  test "upload_file/3 allows unicode filenames" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-unicode-upload.txt")
    File.write!(path, "hello")

    assert {:ok, file} =
             Drive.upload_file(workspace.scope, %{}, %{
               path: path,
               client_name: "мой файл.txt",
               content_type: "text/plain",
               size: 5
             })

    assert file.name == "мой файл.txt"
  end

  test "rename_folder/3 allows renaming to same name (no-op)" do
    workspace = workspace_fixture()
    {:ok, folder} = Drive.create_folder(workspace.scope, %{name: "Drafts"})

    assert {:ok, renamed} = Drive.rename_folder(workspace.scope, folder.id, %{name: "Drafts"})
    assert renamed.name == "Drafts"
  end

  test "rename_file/3 allows renaming to same name (no-op)" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-same-name.txt")
    File.write!(path, "hello")

    {:ok, file} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "doc.txt",
        content_type: "text/plain",
        size: 5
      })

    assert {:ok, renamed} = Drive.rename_file(workspace.scope, file.id, %{name: "doc.txt"})
    assert renamed.name == "doc.txt"
  end

  test "list_trash/1 shows only root trashed folders" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-nested-trash.txt")
    File.write!(path, "hello")

    {:ok, root} = Drive.create_folder(workspace.scope, %{name: "Archive"})

    {:ok, child} =
      Drive.create_folder(workspace.scope, %{name: "Invoices", parent_folder_id: root.id})

    {:ok, _file} =
      Drive.upload_file(workspace.scope, %{folder_id: child.id}, %{
        path: path,
        client_name: "invoice.txt",
        content_type: "text/plain",
        size: 5
      })

    assert {:ok, _} = Drive.soft_delete_node(workspace.scope, {:folder, root.id})

    trashed_folders = Drive.list_trash(workspace.scope).folders
    assert length(trashed_folders) == 1
    assert hd(trashed_folders).id == root.id

    assert [] = Drive.list_trash(workspace.scope).files
  end

  test "workspace_used_size/1 calculates correct total" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-size-test.txt")
    File.write!(path, "hello")

    {:ok, _file1} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "a.txt",
        content_type: "text/plain",
        size: 5
      })

    {:ok, _file2} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "b.txt",
        content_type: "text/plain",
        size: 10
      })

    assert Drive.workspace_used_size(workspace.scope) == 15
  end

  test "workspace_used_size/1 excludes trashed files" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-size-trash.txt")
    File.write!(path, "hello")

    {:ok, _file1} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "keep.txt",
        content_type: "text/plain",
        size: 5
      })

    {:ok, file2} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "trash.txt",
        content_type: "text/plain",
        size: 10
      })

    assert {:ok, _} = Drive.soft_delete_node(workspace.scope, {:file, file2.id})

    assert Drive.workspace_used_size(workspace.scope) == 5
  end

  test "bulk_download_sources/2 returns error for empty list" do
    workspace = workspace_fixture()

    assert {:error, :not_found} = Drive.bulk_download_sources(workspace.scope, [])
  end

  test "bulk_download_sources/2 returns error when all files not found" do
    workspace = workspace_fixture()

    assert {:error, :not_found} = Drive.bulk_download_sources(workspace.scope, [99_998, 99_999])
  end

  test "create_folder/2 inside soft-deleted parent fails" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-deleted-parent.txt")
    File.write!(path, "hello")

    {:ok, parent} = Drive.create_folder(workspace.scope, %{name: "Parent"})
    assert {:ok, _} = Drive.soft_delete_node(workspace.scope, {:folder, parent.id})

    assert {:error, :invalid_parent_folder} =
             Drive.create_folder(workspace.scope, %{name: "Child", parent_folder_id: parent.id})
  end

  test "upload_file/3 inside soft-deleted parent fails" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-upload-deleted.txt")
    File.write!(path, "hello")

    {:ok, folder} = Drive.create_folder(workspace.scope, %{name: "Folder"})
    assert {:ok, _} = Drive.soft_delete_node(workspace.scope, {:folder, folder.id})

    assert {:error, :invalid_parent_folder} =
             Drive.upload_file(workspace.scope, %{folder_id: folder.id}, %{
               path: path,
               client_name: "doc.txt",
               content_type: "text/plain",
               size: 5
             })
  end

  test "prepare_direct_upload/2 rejects folder_id from another tenant" do
    workspace_a = workspace_fixture()
    workspace_b = workspace_fixture()

    {:ok, folder} = Drive.create_folder(workspace_a.scope, %{name: "Secret"})

    assert {:error, :invalid_parent_folder} =
             Drive.prepare_direct_upload(workspace_b.scope, %{
               "name" => "leak.txt",
               "content_type" => "text/plain",
               "size" => "100",
               "folder_id" => folder.id
             })
  end

  test "rename_file/3 rejects duplicate name with another file" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-rename-conflict.txt")
    File.write!(path, "hello")

    {:ok, _file_a} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "report.txt",
        content_type: "text/plain",
        size: 5
      })

    {:ok, file_b} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "other.txt",
        content_type: "text/plain",
        size: 5
      })

    assert {:error, :name_conflict} =
             Drive.rename_file(workspace.scope, file_b.id, %{name: "report.txt"})
  end

  test "rename_folder/3 rejects duplicate name with another folder" do
    workspace = workspace_fixture()
    {:ok, _folder_a} = Drive.create_folder(workspace.scope, %{name: "Finance"})
    {:ok, folder_b} = Drive.create_folder(workspace.scope, %{name: "Legal"})

    assert {:error, :name_conflict} =
             Drive.rename_folder(workspace.scope, folder_b.id, %{name: "Finance"})
  end

  test "rename_file/3 rejects name that conflicts with a folder" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-rename-folder-conflict.txt")
    File.write!(path, "hello")

    {:ok, _folder} = Drive.create_folder(workspace.scope, %{name: "Contracts"})

    {:ok, file} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "draft.txt",
        content_type: "text/plain",
        size: 5
      })

    assert {:error, :name_conflict} =
             Drive.rename_file(workspace.scope, file.id, %{name: "Contracts"})
  end

  test "restore_node/2 rejects file when active file already has same name" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-restore-file-conflict.txt")
    File.write!(path, "hello")

    {:ok, original} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "budget.xlsx",
        content_type: "text/plain",
        size: 5
      })

    assert {:ok, _} = Drive.soft_delete_node(workspace.scope, {:file, original.id})

    {:ok, _replacement} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "budget.xlsx",
        content_type: "text/plain",
        size: 5
      })

    assert {:error, :name_conflict} = Drive.restore_node(workspace.scope, {:file, original.id})
  end

  test "concurrent uploads with same name produce unique files" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-concurrent.txt")
    File.write!(path, "hello")

    upload_attrs = %{
      path: path,
      client_name: "report.txt",
      content_type: "text/plain",
      size: 5
    }

    results =
      1..5
      |> Enum.map(fn _ ->
        Task.async(fn -> Drive.upload_file(workspace.scope, %{}, upload_attrs) end)
      end)
      |> Enum.map(&Task.await/1)

    assert Enum.all?(results, fn {:ok, file} -> is_binary(file.name) end)

    names = Enum.map(results, fn {:ok, f} -> f.name end)
    assert Enum.uniq(names) == names
  end

  test "download_url/2 returns error after file is soft-deleted" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-download-toctou.txt")
    File.write!(path, "hello")

    {:ok, file} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "sensitive.txt",
        content_type: "text/plain",
        size: 5
      })

    assert {:ok, _url} = Drive.download_url(workspace.scope, file.id)

    assert {:ok, _} = Drive.soft_delete_node(workspace.scope, {:file, file.id})

    assert {:error, :not_found} = Drive.download_url(workspace.scope, file.id)
  end
end
