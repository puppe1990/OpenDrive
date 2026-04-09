defmodule OpenDriveWeb.DirectUploadControllerTest do
  use OpenDriveWeb.ConnCase

  import OpenDrive.AccountsFixtures

  alias OpenDrive.Drive
  alias OpenDrive.Repo

  defmodule ExitingStorage do
    @behaviour OpenDrive.Storage

    def put_object(_key, _source, _opts), do: exit(:timeout)
    def presigned_upload_url(_key, _opts), do: {:error, :boom}
    def head_object(_key), do: {:error, :boom}
    def delete_object(_key), do: :ok
    def move_object(_source_key, _destination_key, _opts), do: {:error, :boom}
    def presigned_download_url(_key, _opts), do: {:error, :boom}
  end

  test "creates a direct upload session for an authenticated user", %{conn: conn} do
    workspace = workspace_fixture()
    conn = log_in_user(conn, workspace.user, workspace.scope)

    conn =
      post(conn, ~p"/app/uploads", %{
        "upload" => %{
          "name" => "demo.txt",
          "content_type" => "text/plain",
          "size" => "5"
        }
      })

    assert %{
             "name" => "demo.txt",
             "upload_url" => upload_url,
             "upload_headers" => %{"content-type" => "text/plain"},
             "token" => token
           } = json_response(conn, 200)

    assert is_binary(upload_url)
    assert is_binary(token)
  end

  test "completes a direct upload after the object reaches storage", %{conn: conn} do
    workspace = workspace_fixture()
    conn = log_in_user(conn, workspace.user, workspace.scope)

    conn =
      post(conn, ~p"/app/uploads", %{
        "upload" => %{
          "name" => "demo.txt",
          "content_type" => "text/plain",
          "size" => "5"
        }
      })

    %{"token" => token} = json_response(conn, 200)

    {:ok, upload} =
      Phoenix.Token.verify(OpenDriveWeb.Endpoint, "direct-upload", token, max_age: 3600)

    assert {:ok, _} =
             OpenDrive.Storage.put_object(upload.key, "hello", content_type: "text/plain")

    conn =
      build_conn()
      |> log_in_user(workspace.user, workspace.scope)
      |> post(~p"/app/uploads/complete", %{"token" => token})

    assert %{"ok" => true, "name" => "demo.txt"} = json_response(conn, 200)
    assert [%{name: "demo.txt"}] = Drive.list_children(workspace.scope).files
  end

  test "auto-renames duplicate names during direct upload preparation", %{conn: conn} do
    workspace = workspace_fixture()
    conn = log_in_user(conn, workspace.user, workspace.scope)

    upload =
      %Plug.Upload{
        path: write_temp_file!("open-drive-proxy-duplicate.txt", "hello"),
        filename: "demo.txt",
        content_type: "text/plain"
      }

    conn
    |> post(~p"/app/uploads/proxy", %{"file" => upload, "name" => "demo.txt"})
    |> json_response(200)

    conn =
      post(conn, ~p"/app/uploads", %{
        "upload" => %{
          "name" => "demo.txt",
          "content_type" => "text/plain",
          "size" => "5"
        }
      })

    assert %{"name" => "demo (2).txt"} = json_response(conn, 200)
  end

  test "rejects completing a direct upload after switching workspace", %{conn: conn} do
    workspace = workspace_fixture()
    other_workspace = workspace_fixture(%{user: workspace.user, tenant_name: "Other Workspace"})

    conn =
      conn
      |> log_in_user(workspace.user, workspace.scope)
      |> post(~p"/app/uploads", %{
        "upload" => %{
          "name" => "demo.txt",
          "content_type" => "text/plain",
          "size" => "5"
        }
      })

    %{"token" => token} = json_response(conn, 200)

    {:ok, upload} =
      Phoenix.Token.verify(OpenDriveWeb.Endpoint, "direct-upload", token, max_age: 3600)

    assert {:ok, _} =
             OpenDrive.Storage.put_object(upload.key, "hello", content_type: "text/plain")

    conn =
      build_conn()
      |> log_in_user(workspace.user, other_workspace.scope)
      |> post(~p"/app/uploads/complete", %{"token" => token})

    assert %{"error" => error} = json_response(conn, 403)
    assert error =~ "different workspace or user"
    assert [] = Drive.list_children(other_workspace.scope).files
  end

  test "proxies a small upload through the backend", %{conn: conn} do
    workspace = workspace_fixture()

    upload =
      %Plug.Upload{
        path: write_temp_file!("open-drive-proxy-upload.txt", "hello proxy"),
        filename: "proxy.txt",
        content_type: "text/plain"
      }

    conn =
      conn
      |> log_in_user(workspace.user, workspace.scope)
      |> post(~p"/app/uploads/proxy", %{"file" => upload, "name" => "proxy.txt"})

    assert %{"ok" => true, "name" => "proxy.txt"} = json_response(conn, 200)
    assert Repo.aggregate(OpenDrive.Drive.FileObject, :count) == 1
    assert [%{name: "proxy.txt"}] = Drive.list_children(workspace.scope).files
  end

  test "rejects proxy uploads above the backend fallback limit", %{conn: conn} do
    workspace = workspace_fixture()

    upload =
      %Plug.Upload{
        path:
          write_sparse_temp_file!(
            "open-drive-proxy-too-large.bin",
            Drive.backend_upload_fallback_size() + 1
          ),
        filename: "too-large.bin",
        content_type: "application/octet-stream"
      }

    conn =
      conn
      |> log_in_user(workspace.user, workspace.scope)
      |> post(~p"/app/uploads/proxy", %{"file" => upload, "name" => "too-large.bin"})

    assert conn.status in [413, 422]
  end

  test "returns a structured error when proxy storage exits", %{conn: conn} do
    original = Application.get_env(:open_drive, OpenDrive.Storage)

    Application.put_env(
      :open_drive,
      OpenDrive.Storage,
      Keyword.put(original, :adapter, ExitingStorage)
    )

    on_exit(fn -> Application.put_env(:open_drive, OpenDrive.Storage, original) end)

    workspace = workspace_fixture()

    upload =
      %Plug.Upload{
        path: write_temp_file!("open-drive-proxy-storage-exit.txt", "hello proxy"),
        filename: "proxy.txt",
        content_type: "text/plain"
      }

    conn =
      conn
      |> log_in_user(workspace.user, workspace.scope)
      |> post(~p"/app/uploads/proxy", %{"file" => upload, "name" => "proxy.txt"})

    assert conn.status == 503
    assert %{"error" => error} = json_response(conn, 503)
    assert error =~ "storage"
  end

  defp write_temp_file!(name, contents) do
    path = Path.join(System.tmp_dir!(), name)
    File.write!(path, contents)
    path
  end

  defp write_sparse_temp_file!(name, size) do
    path = Path.join(System.tmp_dir!(), name)
    {:ok, file} = File.open(path, [:write, :binary])
    {:ok, _position} = :file.position(file, size - 1)
    :ok = IO.binwrite(file, <<0>>)
    File.close(file)
    path
  end
end
