defmodule OpenDriveWeb.FolderUploadControllerTest do
  use OpenDriveWeb.ConnCase

  import OpenDrive.AccountsFixtures

  alias OpenDrive.Drive

  test "creates a folder for upload flows and suffixes conflicting names", %{conn: conn} do
    workspace = workspace_fixture()
    {:ok, parent} = Drive.create_folder(workspace.scope, %{name: "Imports"})

    {:ok, _existing} =
      Drive.create_folder(workspace.scope, %{name: "Photos", parent_folder_id: parent.id})

    conn =
      conn
      |> log_in_user(workspace.user, workspace.scope)
      |> post("/app/folders/upload", %{
        "folder" => %{"name" => "Photos", "parent_folder_id" => parent.id}
      })

    assert %{"id" => id, "name" => "Photos (2)"} = json_response(conn, 200)

    assert Enum.any?(
             Drive.list_children(workspace.scope, parent.id).folders,
             &(&1.id == id and &1.name == "Photos (2)")
           )
  end
end
