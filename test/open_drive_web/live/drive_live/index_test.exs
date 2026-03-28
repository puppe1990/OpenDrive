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

  test "uploads a file automatically from the drive screen", %{conn: conn} do
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

    render_upload(upload, "notes.txt")
    html = render(lv)
    assert html =~ "Upload complete."

    [file] = Drive.list_children(workspace.scope).files
    assert file.name == "notes.txt"
    assert file.file_object.content_type == "text/plain"
    assert Repo.aggregate(OpenDrive.Drive.FileObject, :count) == 1
  end

  test "renders an automatic drag and drop area for the current folder", %{conn: conn} do
    workspace = workspace_fixture(%{tenant_name: "Drop Space"})

    conn = log_in_user(conn, workspace.user, workspace.scope)
    {:ok, _lv, html} = live(conn, ~p"/app")

    assert html =~ "Arraste arquivos para esta pasta"
    assert html =~ "O upload comeca assim que voce solta o arquivo"
    assert html =~ "Voce pode soltar varios arquivos por vez"
    assert html =~ ~s(id="folder-dropzone")
    assert html =~ ~s(phx-drop-target=)
    assert html =~ "data-phx-auto-upload"
    assert html =~ ~s(type="file")
    refute html =~ "Enviar arquivo"
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

  test "opens the image carousel and advances to the next visible photo", %{conn: conn} do
    workspace = workspace_fixture(%{tenant_name: "Gallery Space"})
    first_path = Path.join(System.tmp_dir!(), "open_drive-gallery-first.webp")
    second_path = Path.join(System.tmp_dir!(), "open_drive-gallery-second.webp")

    File.write!(first_path, "first image")
    File.write!(second_path, "second image")

    {:ok, first} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: first_path,
        client_name: "first.webp",
        content_type: "image/webp",
        size: byte_size("first image")
      })

    {:ok, _second} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: second_path,
        client_name: "second.webp",
        content_type: "image/webp",
        size: byte_size("second image")
      })

    conn = log_in_user(conn, workspace.user, workspace.scope)
    {:ok, lv, _html} = live(conn, ~p"/app")

    html =
      lv
      |> element("button[phx-click='open_image'][phx-value-id='#{first.id}']")
      |> render_click()

    assert html =~ "first.webp"

    html =
      lv
      |> element("button[phx-click='next_image'][aria-label='Proxima foto']")
      |> render_click()

    assert html =~ "second.webp"

    html =
      lv
      |> render_keydown("image_keydown", %{"key" => "ArrowLeft"})

    assert html =~ "first.webp"

    html =
      lv
      |> render_keydown("image_keydown", %{"key" => "ArrowRight"})

    assert html =~ "second.webp"
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
