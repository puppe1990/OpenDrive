defmodule OpenDriveWeb.DriveLive.EntriesTest do
  use OpenDrive.DataCase

  import OpenDrive.AccountsFixtures

  alias OpenDrive.Drive
  alias OpenDrive.Storage
  alias OpenDriveWeb.DriveLive.Entries

  @controls %{"query" => "", "type" => "all", "sort" => "modified_desc"}

  test "media entries preview from storage URLs and keep downloads on the app route" do
    workspace = workspace_fixture()
    image_path = Path.join(System.tmp_dir!(), "open_drive-entries-image.webp")
    File.write!(image_path, "fake image")

    {:ok, image} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: image_path,
        client_name: "cover.webp",
        content_type: "image/webp",
        size: byte_size("fake image")
      })

    children = Drive.list_children(workspace.scope)
    [entry] = Entries.apply(children, @controls)
    {:ok, expected_media_url} = Storage.presigned_download_url(image.file_object.key)

    assert entry.preview == :image
    assert entry.media_url == expected_media_url
    assert entry.href == "/app/files/#{image.id}/download"
    refute String.contains?(entry.media_url, "/app/files/")
  end

  test "plain files have no media URL" do
    workspace = workspace_fixture()
    path = Path.join(System.tmp_dir!(), "open_drive-entries-plain.txt")
    File.write!(path, "notes")

    {:ok, file} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "notes.txt",
        content_type: "text/plain",
        size: byte_size("notes")
      })

    children = Drive.list_children(workspace.scope)
    [entry] = Entries.apply(children, @controls)

    assert entry.preview == :file
    assert entry.media_url == nil
    assert entry.href == "/app/files/#{file.id}/download"
  end
end
