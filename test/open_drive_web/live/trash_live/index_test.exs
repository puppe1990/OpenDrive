defmodule OpenDriveWeb.TrashLive.IndexTest do
  use OpenDriveWeb.ConnCase

  import Phoenix.LiveViewTest
  alias OpenDrive.Drive

  setup :register_and_log_in_user

  test "renders trash page in pt-BR by default", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/app/trash")

    assert html =~ ~s(lang="pt-BR")
    assert html =~ "Lixeira"
  end

  test "renders trash page in english when locale=en", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/app/trash?locale=en")

    assert html =~ ~s(lang="en")
    assert html =~ "Trash"
    assert html =~ "Empty trash"
  end

  test "empties trash after confirmation", %{conn: conn, scope: scope} do
    {:ok, _file} =
      Drive.upload_file(scope, %{}, %{
        path: write_temp_file!("trash-processing.txt", "trash me"),
        client_name: "trash-processing.txt",
        content_type: "text/plain",
        size: 8
      })

    [file] = Drive.list_children(scope).files
    assert {:ok, _} = Drive.soft_delete_node(scope, {:file, file.id})

    {:ok, view, _html} = live(conn, ~p"/app/trash?locale=en")

    assert has_element?(view, "button[phx-click=\"open_empty_trash_modal\"]", "Empty trash")

    view
    |> element("button[phx-click=\"open_empty_trash_modal\"]")
    |> render_click()

    assert has_element?(view, "h2", "Delete permanently?")
    assert has_element?(view, "button[phx-click=\"cancel_empty_trash\"]", "Cancel")
    assert has_element?(view, "button[phx-click=\"empty_trash\"]")

    view
    |> element("button[phx-click=\"empty_trash\"]")
    |> render_click()

    refute has_element?(view, "h2", "Delete permanently?")
    assert render(view) =~ "Trash emptied."
    assert Drive.list_trash(scope).files == []
    assert Drive.list_trash(scope).folders == []
  end

  defp write_temp_file!(name, contents) do
    unique_name = "#{System.unique_integer([:positive])}-#{name}"
    path = Path.join(System.tmp_dir!(), unique_name)

    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)

    path
  end
end
