defmodule OpenDriveWeb.DriveLive.IndexTest do
  use OpenDriveWeb.ConnCase

  import Phoenix.LiveViewTest
  import OpenDrive.AccountsFixtures

  alias OpenDrive.Drive
  alias OpenDrive.Repo

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

  test "uploads a file from the drive screen", %{conn: conn} do
    workspace = workspace_fixture(%{tenant_name: "Upload Space"})

    conn = log_in_user(conn, workspace.user, workspace.scope)
    {:ok, lv, _html} = live(conn, ~p"/app")

    upload =
      file_input(lv, "#upload_form", :files, [
        %{
          last_modified: 1_700_000_000_000,
          name: "notes.txt",
          content: "hello upload",
          size: byte_size("hello upload"),
          type: "text/plain"
        }
      ])

    assert render_upload(upload, "notes.txt") =~ "100%"
    assert render_submit(form(lv, "#upload_form", %{})) =~ "Upload complete."

    [file] = Drive.list_children(workspace.scope).files
    assert file.name == "notes.txt"
    assert file.file_object.content_type == "text/plain"
    assert Repo.aggregate(OpenDrive.Drive.FileObject, :count) == 1
  end

  test "renders preview markup for image and video files", %{conn: conn} do
    workspace = workspace_fixture(%{tenant_name: "Preview Space"})
    image_path = Path.join(System.tmp_dir!(), "open_drive-preview-image.webp")
    video_path = Path.join(System.tmp_dir!(), "open_drive-preview-video.mp4")

    File.write!(image_path, "fake image")
    File.write!(video_path, "fake video")

    {:ok, _image} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: image_path,
        client_name: "cover.webp",
        content_type: "image/webp",
        size: byte_size("fake image")
      })

    {:ok, _video} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: video_path,
        client_name: "clip.mp4",
        content_type: "video/mp4",
        size: byte_size("fake video")
      })

    conn = log_in_user(conn, workspace.user, workspace.scope)
    {:ok, _lv, html} = live(conn, ~p"/app")

    assert html =~ ~s(src="/app/files/)
    assert html =~ "<img"
    assert html =~ "<video"
  end

  test "filters and switches between grid and list controls", %{conn: conn} do
    workspace = workspace_fixture(%{tenant_name: "Control Space"})
    {:ok, _folder} = Drive.create_folder(workspace.scope, %{name: "Invoices"})
    path = Path.join(System.tmp_dir!(), "open_drive-controls.txt")
    File.write!(path, "control file")

    {:ok, _file} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "report.txt",
        content_type: "text/plain",
        size: byte_size("control file")
      })

    conn = log_in_user(conn, workspace.user, workspace.scope)
    {:ok, lv, html} = live(conn, ~p"/app")

    assert html =~ "Meu Drive"
    assert html =~ "Invoices"
    assert html =~ "report.txt"

    html =
      render_change(
        form(lv, "#controls_form",
          controls: %{query: "report", type: "files", sort: "name_asc", view: "grid"}
        )
      )

    assert html =~ "report.txt"
    refute html =~ "Invoices"

    html = render_click(element(lv, "button[phx-value-view='list']"))
    assert html =~ "Modificado"
    assert html =~ "report.txt"
  end
end
