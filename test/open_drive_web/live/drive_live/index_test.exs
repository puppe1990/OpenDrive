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

  test "renders an automatic drag and drop area for the current folder", %{conn: conn} do
    workspace = workspace_fixture(%{tenant_name: "Drop Space"})

    conn = log_in_user(conn, workspace.user, workspace.scope)
    {:ok, _lv, html} = live(conn, ~p"/app")

    assert html =~ "Arraste arquivos para esta pasta"
    assert html =~ "O upload comeca assim que voce solta o arquivo"
    assert html =~ "Voce pode soltar varios arquivos por vez"
    assert html =~ ~s(id="folder-dropzone")
    assert html =~ ~s(phx-hook="DirectUploadZone")
    assert html =~ "data-direct-upload-input"
    assert html =~ ~s(type="file")
    assert html =~ "Fila de uploads"
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
    assert html =~ ~s(phx-click="open_video")
    assert html =~ "Abrir player"
  end

  test "shows used workspace storage in the sidebar card", %{conn: conn} do
    workspace = workspace_fixture(%{tenant_name: "Usage Space"})
    first_path = Path.join(System.tmp_dir!(), "open_drive-usage-first.txt")
    second_path = Path.join(System.tmp_dir!(), "open_drive-usage-second.txt")

    File.write!(first_path, "12345")
    File.write!(second_path, "1234567890")

    {:ok, _first} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: first_path,
        client_name: "first.txt",
        content_type: "text/plain",
        size: 5
      })

    {:ok, _second} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: second_path,
        client_name: "second.txt",
        content_type: "text/plain",
        size: 10
      })

    conn = log_in_user(conn, workspace.user, workspace.scope)
    {:ok, _lv, html} = live(conn, ~p"/app")

    assert html =~ "15 B usados no workspace"
  end

  test "renames an already uploaded file from the drive list", %{conn: conn} do
    workspace = workspace_fixture(%{tenant_name: "Rename Existing Space"})
    path = Path.join(System.tmp_dir!(), "open_drive-existing-rename.txt")
    File.write!(path, "rename me")

    {:ok, file} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: path,
        client_name: "draft.txt",
        content_type: "text/plain",
        size: byte_size("rename me")
      })

    old_key = file.file_object.key

    conn = log_in_user(conn, workspace.user, workspace.scope)
    {:ok, lv, _html} = live(conn, ~p"/app")

    html =
      lv
      |> element("button[phx-click='start_rename_file'][phx-value-id='#{file.id}']")
      |> render_click()

    assert html =~ "Renomear arquivo"
    assert html =~ "a key do arquivo sera movida no S3"
    assert html =~ "Salvar"

    html =
      lv
      |> element("form[phx-submit='rename_file']")
      |> render_submit(%{"file_id" => "#{file.id}", "rename" => %{"name" => "final.txt"}})

    assert html =~ "File renamed."
    assert html =~ "final.txt"

    [renamed_file] = Drive.list_children(workspace.scope).files
    assert renamed_file.name == "final.txt"
    refute renamed_file.file_object.key == old_key
    assert String.contains?(renamed_file.file_object.key, "final")
  end

  test "asks for confirmation before deleting a folder", %{conn: conn} do
    workspace = workspace_fixture(%{tenant_name: "Folder Delete Space"})
    {:ok, folder} = Drive.create_folder(workspace.scope, %{name: "Invoices"})

    conn = log_in_user(conn, workspace.user, workspace.scope)
    {:ok, lv, _html} = live(conn, ~p"/app")

    html =
      lv
      |> element("button[phx-click='delete_folder'][phx-value-id='#{folder.id}']")
      |> render_click()

    assert html =~ "Deletar pasta"
    assert html =~ "Tem certeza?"
    assert html =~ "Invoices"

    html =
      lv
      |> element("button[phx-click='confirm_delete_folder'][phx-value-id='#{folder.id}']")
      |> render_click()

    refute html =~ "Invoices"
    assert Drive.list_children(workspace.scope).folders == []
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

  test "opens the video in a modal player", %{conn: conn} do
    workspace = workspace_fixture(%{tenant_name: "Video Modal Space"})
    video_path = Path.join(System.tmp_dir!(), "open_drive-modal-video.mp4")
    File.write!(video_path, "fake video")

    {:ok, video} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: video_path,
        client_name: "demo.mp4",
        content_type: "video/mp4",
        size: byte_size("fake video")
      })

    conn = log_in_user(conn, workspace.user, workspace.scope)
    {:ok, lv, _html} = live(conn, ~p"/app")

    html =
      lv
      |> element("button[phx-click='open_video'][phx-value-id='#{video.id}']")
      |> render_click()

    assert html =~ "OpenDrive Player"
    assert html =~ "demo.mp4"
    assert html =~ ~s(id="video-modal-#{video.id}")
    assert html =~ "Atalhos do teclado"
    assert html =~ "Play / Pause"
    assert html =~ "Fullscreen"
    assert html =~ ~s(data-role="preview-popover")
    assert html =~ ~s(data-role="preview-canvas")
    assert html =~ ~s(data-role="volume")
    assert html =~ "Volume do video"

    html =
      lv
      |> element("button[phx-click='close_video'][aria-label='Fechar']")
      |> render_click()

    refute html =~ "OpenDrive Player"
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

  test "selects rows in list mode and deletes selected items in bulk", %{conn: conn} do
    workspace = workspace_fixture(%{tenant_name: "Bulk Action Space"})
    first_path = Path.join(System.tmp_dir!(), "open_drive-bulk-first.txt")
    second_path = Path.join(System.tmp_dir!(), "open_drive-bulk-second.txt")

    File.write!(first_path, "first bulk file")
    File.write!(second_path, "second bulk file")

    {:ok, first_file} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: first_path,
        client_name: "first.txt",
        content_type: "text/plain",
        size: byte_size("first bulk file")
      })

    {:ok, second_file} =
      Drive.upload_file(workspace.scope, %{}, %{
        path: second_path,
        client_name: "second.txt",
        content_type: "text/plain",
        size: byte_size("second bulk file")
      })

    conn = log_in_user(conn, workspace.user, workspace.scope)
    {:ok, lv, _html} = live(conn, ~p"/app")

    html = render_click(element(lv, "button[phx-value-view='list']"))
    assert html =~ "Selecionar todos"
    assert html =~ "Baixar ZIP"

    html =
      lv
      |> element(
        "input[phx-click='toggle_entry_selection'][phx-value-key='file:#{first_file.id}']"
      )
      |> render_click()

    assert html =~ "Selecionados: 1"
    assert html =~ "1 arquivo(s) para ZIP"

    html =
      lv
      |> element(
        "input[phx-click='toggle_entry_selection'][phx-value-key='file:#{second_file.id}']"
      )
      |> render_click()

    assert html =~ "Selecionados: 2"

    html =
      lv
      |> element("button[phx-click='open_bulk_delete_modal']")
      |> render_click()

    assert html =~ "Confirmar exclusao"
    assert html =~ "first.txt"
    assert html =~ "second.txt"

    html =
      lv
      |> element("button[phx-click='confirm_bulk_delete']")
      |> render_click()

    assert html =~ "2 item(ns) enviado(s) para a lixeira."
    refute html =~ "first.txt"
    refute html =~ "second.txt"
    assert Drive.list_children(workspace.scope).files == []
  end
end
