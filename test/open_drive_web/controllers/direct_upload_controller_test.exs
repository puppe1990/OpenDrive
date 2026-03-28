defmodule OpenDriveWeb.DirectUploadControllerTest do
  use OpenDriveWeb.ConnCase

  import OpenDrive.AccountsFixtures

  alias OpenDrive.Drive
  alias OpenDrive.Repo

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

    assert %{"ok" => true} = json_response(conn, 200)
    assert [%{name: "demo.txt"}] = Drive.list_children(workspace.scope).files
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

  defp write_temp_file!(name, contents) do
    path = Path.join(System.tmp_dir!(), name)
    File.write!(path, contents)
    path
  end
end
