defmodule OpenDriveWeb.DriveLive.IndexTest do
  use OpenDriveWeb.ConnCase

  import Phoenix.LiveViewTest
  import OpenDrive.AccountsFixtures

  alias OpenDrive.Drive

  test "shows folders from the current tenant only", %{conn: conn} do
    workspace = workspace_fixture(%{tenant_name: "Primary Space"})
    _other = workspace_fixture(%{tenant_name: "Hidden Space"})
    {:ok, folder} = Drive.create_folder(workspace.scope, %{name: "Roadmap"})

    conn = log_in_user(conn, workspace.user, workspace.scope)
    {:ok, _lv, html} = live(conn, ~p"/app")

    assert html =~ "Primary Space"
    assert html =~ folder.name
    refute html =~ "Hidden Space"
  end
end
