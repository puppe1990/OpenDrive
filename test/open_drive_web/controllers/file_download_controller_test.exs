defmodule OpenDriveWeb.FileDownloadControllerTest do
  use OpenDriveWeb.ConnCase

  import OpenDrive.AccountsFixtures

  alias OpenDrive.Drive

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
end
