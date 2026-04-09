defmodule OpenDriveWeb.FileDownloadControllerTest do
  use OpenDriveWeb.ConnCase

  import OpenDrive.AccountsFixtures

  alias OpenDrive.Drive

  test "serves local storage files inline for previewable media", %{conn: conn} do
    workspace = workspace_fixture(%{tenant_name: "Media Space"})
    path = Path.join(System.tmp_dir!(), "open_drive-preview-video.mp4")
    body = "fake-video-binary"
    File.write!(path, body)

    {:ok, file} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "preview.mp4",
        content_type: "video/mp4",
        size: byte_size(body)
      })

    conn =
      conn
      |> log_in_user(workspace.user, workspace.scope)
      |> get(~p"/app/files/#{file.id}/download")

    assert conn.status == 200
    assert conn.resp_body == body
    assert get_resp_header(conn, "content-type") == ["video/mp4"]
    assert get_resp_header(conn, "accept-ranges") == ["bytes"]
  end

  test "supports byte range requests for local storage files", %{conn: conn} do
    workspace = workspace_fixture(%{tenant_name: "Media Range Space"})
    path = Path.join(System.tmp_dir!(), "open_drive-range-video.mp4")
    body = "0123456789"
    File.write!(path, body)

    {:ok, file} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "range.mp4",
        content_type: "video/mp4",
        size: byte_size(body)
      })

    conn =
      conn
      |> log_in_user(workspace.user, workspace.scope)
      |> put_req_header("range", "bytes=2-5")
      |> get(~p"/app/files/#{file.id}/download")

    assert conn.status == 206
    assert conn.resp_body == "2345"
    assert get_resp_header(conn, "content-range") == ["bytes 2-5/10"]
    assert get_resp_header(conn, "accept-ranges") == ["bytes"]
    assert get_resp_header(conn, "content-type") == ["video/mp4"]
  end

  test "redirects with an error when a local storage blob is missing", %{conn: conn} do
    workspace = workspace_fixture(%{tenant_name: "Missing Blob Space"})
    path = Path.join(System.tmp_dir!(), "open_drive-missing-video.mp4")
    body = "fake-video-binary"
    File.write!(path, body)

    {:ok, file} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "missing.mp4",
        content_type: "video/mp4",
        size: byte_size(body)
      })

    blob_path =
      Path.join([
        System.tmp_dir!(),
        "open_drive_storage",
        OpenDrive.Storage.bucket(),
        file.file_object.key
      ])

    File.rm!(blob_path)

    conn =
      conn
      |> log_in_user(workspace.user, workspace.scope)
      |> get(~p"/app/files/#{file.id}/download")

    assert redirected_to(conn) == ~p"/app"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Arquivo nao encontrado."
  end

  test "downloads selected files as a zip", %{conn: conn} do
    workspace = workspace_fixture(%{tenant_name: "Zip Space"})
    first_path = Path.join(System.tmp_dir!(), "open_drive-zip-first.txt")
    second_path = Path.join(System.tmp_dir!(), "open_drive-zip-second.txt")

    File.write!(first_path, "zip first")
    File.write!(second_path, "zip second")

    {:ok, first_file} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: first_path,
        client_name: "first.txt",
        content_type: "text/plain",
        size: byte_size("zip first")
      })

    {:ok, second_file} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: second_path,
        client_name: "second.txt",
        content_type: "text/plain",
        size: byte_size("zip second")
      })

    conn =
      conn
      |> log_in_user(workspace.user, workspace.scope)
      |> post(~p"/app/files/download-zip", %{
        "file_ids" => [Integer.to_string(first_file.id), Integer.to_string(second_file.id)]
      })

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["application/zip"]

    [content_disposition] = get_resp_header(conn, "content-disposition")
    assert content_disposition =~ "attachment;"
    assert content_disposition =~ ".zip"
    assert binary_part(conn.resp_body, 0, 2) == "PK"

    zip_path = Path.join(System.tmp_dir!(), "open_drive-selected-files-test.zip")
    extract_dir = Path.join(System.tmp_dir!(), "open_drive-selected-files-test")

    File.rm_rf!(extract_dir)
    File.write!(zip_path, conn.resp_body)
    File.mkdir_p!(extract_dir)

    assert {:ok, _files} =
             :zip.extract(String.to_charlist(zip_path), cwd: String.to_charlist(extract_dir))

    assert File.read!(Path.join(extract_dir, "first-1.txt")) == "zip first"
    assert File.read!(Path.join(extract_dir, "second-2.txt")) == "zip second"
  end

  test "rejects zip downloads above the synchronous size limit", %{conn: conn} do
    workspace = workspace_fixture(%{tenant_name: "Zip Limit Space"})
    path = Path.join(System.tmp_dir!(), "open_drive-zip-limit.bin")
    File.write!(path, "small")

    {:ok, first_file} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "first.bin",
        content_type: "application/octet-stream",
        size: 300 * 1024 * 1024
      })

    {:ok, second_file} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "second.bin",
        content_type: "application/octet-stream",
        size: 300 * 1024 * 1024
      })

    conn =
      conn
      |> log_in_user(workspace.user, workspace.scope)
      |> post(~p"/app/files/download-zip", %{
        "file_ids" => [Integer.to_string(first_file.id), Integer.to_string(second_file.id)]
      })

    assert redirected_to(conn) == ~p"/app"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "100 files and 500 MB"
  end
end
