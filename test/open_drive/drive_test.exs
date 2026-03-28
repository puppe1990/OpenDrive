defmodule OpenDrive.DriveTest do
  use OpenDrive.DataCase

  alias OpenDrive.Drive
  alias OpenDrive.Drive.File, as: DriveFile
  alias OpenDrive.Drive.FileObject
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
      Path.join([System.tmp_dir!(), "open_drive_storage", OpenDrive.Storage.bucket(), file.file_object.key])

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
end
