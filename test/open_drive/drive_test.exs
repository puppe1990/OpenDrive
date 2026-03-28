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
    def delete_object(_key), do: :ok
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
end
