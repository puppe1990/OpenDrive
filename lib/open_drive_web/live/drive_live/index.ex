defmodule OpenDriveWeb.DriveLive.Index do
  use OpenDriveWeb, :live_view

  alias OpenDrive.Drive

  @default_controls %{
    "query" => "",
    "type" => "all",
    "sort" => "modified_desc",
    "view" => "grid"
  }

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:folder_form, to_form(%{"name" => ""}, as: "folder"))
      |> assign(:rename_form, to_form(%{"name" => ""}, as: "rename"))
      |> assign(:controls, @default_controls)
      |> assign(:controls_form, to_form(@default_controls, as: "controls"))
      |> assign(:editing_file_id, nil)
      |> assign(:pending_delete_folder_id, nil)
      |> assign(:pending_delete_file_id, nil)
      |> assign(:confirm_bulk_delete, false)
      |> assign(:new_menu_open, true)
      |> assign(:children, %{folders: [], files: []})
      |> assign(:entries, [])
      |> assign(:selected_entries, MapSet.new())
      |> assign(:selected_image_id, nil)
      |> assign(:selected_video_id, nil)
      |> assign(:workspace_used_size, 0)
      |> assign(:folder_count, 0)
      |> assign(:file_count, 0)
      |> assign(:total_size, 0)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"folder_id" => folder_id}, _uri, socket) do
    {:noreply, load_drive(socket, folder_id)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, load_drive(socket, nil)}
  end

  @impl true
  def handle_event("toggle_new_menu", _params, socket) do
    {:noreply, update(socket, :new_menu_open, &(!&1))}
  end

  def handle_event("update_controls", %{"controls" => params}, socket) do
    socket =
      socket
      |> assign_controls(params)
      |> refresh_entries()

    {:noreply, socket}
  end

  def handle_event("set_sidebar_preset", %{"preset" => preset}, socket) do
    controls =
      case preset do
        "my_drive" ->
          %{
            "query" => "",
            "type" => "all",
            "sort" => "modified_desc",
            "view" => current_view(socket)
          }

        "recent" ->
          %{
            "query" => "",
            "type" => "all",
            "sort" => "modified_desc",
            "view" => current_view(socket)
          }

        "images" ->
          %{
            "query" => "",
            "type" => "images",
            "sort" => "modified_desc",
            "view" => current_view(socket)
          }

        "videos" ->
          %{
            "query" => "",
            "type" => "videos",
            "sort" => "modified_desc",
            "view" => current_view(socket)
          }

        "folders" ->
          %{
            "query" => "",
            "type" => "folders",
            "sort" => "name_asc",
            "view" => current_view(socket)
          }
      end

    socket =
      socket
      |> assign_controls(controls)
      |> refresh_entries()

    {:noreply, socket}
  end

  def handle_event("set_view", %{"view" => view}, socket) do
    socket =
      socket
      |> assign_controls(%{"view" => view})
      |> refresh_entries()

    {:noreply, socket}
  end

  def handle_event("toggle_sort", %{"field" => field}, socket) do
    sort = next_sort(socket.assigns.controls["sort"], field)

    socket =
      socket
      |> assign_controls(%{"sort" => sort})
      |> refresh_entries()

    {:noreply, socket}
  end

  def handle_event("create_folder", %{"folder" => attrs}, socket) do
    attrs = Map.put(attrs, "parent_folder_id", socket.assigns.current_folder_id)

    case Drive.create_folder(socket.assigns.current_scope, attrs) do
      {:ok, _folder} ->
        {:noreply,
         socket
         |> put_flash(:info, "Folder created.")
         |> load_drive(socket.assigns.current_folder_id)}

      {:error, :name_conflict} ->
        {:noreply, put_flash(socket, :error, "Name already used in this folder.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Unable to create folder.")}
    end
  end

  def handle_event("delete_folder", %{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_folder_id, normalize_id(id))}
  end

  def handle_event("cancel_delete_folder", _params, socket) do
    {:noreply, assign(socket, :pending_delete_folder_id, nil)}
  end

  def handle_event("confirm_delete_folder", %{"id" => id}, socket) do
    {:ok, _} = Drive.soft_delete_node(socket.assigns.current_scope, {:folder, id})

    {:noreply,
     socket
     |> assign(:pending_delete_folder_id, nil)
     |> load_drive(socket.assigns.current_folder_id)}
  end

  def handle_event("delete_file", %{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_file_id, normalize_id(id))}
  end

  def handle_event("toggle_entry_selection", %{"key" => key}, socket) do
    visible_keys = visible_entry_keys(socket.assigns.entries)

    socket =
      if MapSet.member?(visible_keys, key) do
        update(socket, :selected_entries, fn selected ->
          if MapSet.member?(selected, key),
            do: MapSet.delete(selected, key),
            else: MapSet.put(selected, key)
        end)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("toggle_all_entries", %{"state" => state}, socket) do
    visible_keys = visible_entry_keys(socket.assigns.entries)

    socket =
      case state do
        "checked" -> assign(socket, :selected_entries, visible_keys)
        _ -> assign(socket, :selected_entries, MapSet.new())
      end

    {:noreply, socket}
  end

  def handle_event("open_bulk_delete_modal", _params, socket) do
    socket =
      if selected_entries(socket.assigns.entries, socket.assigns.selected_entries) == [] do
        socket
      else
        assign(socket, :confirm_bulk_delete, true)
      end

    {:noreply, socket}
  end

  def handle_event("cancel_bulk_delete", _params, socket) do
    {:noreply, assign(socket, :confirm_bulk_delete, false)}
  end

  def handle_event("confirm_bulk_delete", _params, socket) do
    entries = selected_entries(socket.assigns.entries, socket.assigns.selected_entries)

    case bulk_delete_entries(socket.assigns.current_scope, entries) do
      :ok ->
        {:noreply,
         socket
         |> assign(:confirm_bulk_delete, false)
         |> assign(:selected_entries, MapSet.new())
         |> put_flash(:info, "#{length(entries)} item(ns) enviado(s) para a lixeira.")
         |> load_drive(socket.assigns.current_folder_id)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:confirm_bulk_delete, false)
         |> put_flash(:error, "Nao foi possivel deletar os itens selecionados.")}
    end
  end

  def handle_event("cancel_delete_file", _params, socket) do
    {:noreply, assign(socket, :pending_delete_file_id, nil)}
  end

  def handle_event("confirm_delete_file", %{"id" => id}, socket) do
    {:ok, _} = Drive.soft_delete_node(socket.assigns.current_scope, {:file, id})

    {:noreply,
     socket
     |> assign(:pending_delete_file_id, nil)
     |> load_drive(socket.assigns.current_folder_id)}
  end

  def handle_event("start_rename_file", %{"id" => id}, socket) do
    file_id = normalize_id(id)

    case Enum.find(socket.assigns.children.files, &(&1.id == file_id)) do
      nil ->
        {:noreply, socket}

      file ->
        {:noreply,
         socket
         |> assign(:editing_file_id, file_id)
         |> assign(:rename_form, to_form(%{"name" => file.name}, as: "rename"))}
    end
  end

  def handle_event("cancel_rename_file", _params, socket) do
    {:noreply, clear_rename_state(socket)}
  end

  def handle_event("rename_file", %{"file_id" => id, "rename" => %{"name" => name}}, socket) do
    case Drive.rename_file(socket.assigns.current_scope, normalize_id(id), %{name: name}) do
      {:ok, _file} ->
        {:noreply,
         socket
         |> clear_rename_state()
         |> put_flash(:info, "File renamed.")
         |> load_drive(socket.assigns.current_folder_id)}

      {:error, :name_conflict} ->
        {:noreply, put_flash(socket, :error, "Name already used in this folder.")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> clear_rename_state()
         |> put_flash(:error, "File not found.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Unable to rename file.")}
    end
  end

  def handle_event("open_image", %{"id" => id}, socket) do
    image_id = normalize_id(id)

    socket =
      if Enum.any?(visible_images(socket.assigns.entries), &(&1.id == image_id)) do
        assign(socket, :selected_image_id, image_id)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("close_image", _params, socket) do
    {:noreply, assign(socket, :selected_image_id, nil)}
  end

  def handle_event("refresh_after_direct_upload", _params, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Upload complete.")
     |> load_drive(socket.assigns.current_folder_id)}
  end

  def handle_event("open_video", %{"id" => id}, socket) do
    video_id = normalize_id(id)

    socket =
      if Enum.any?(visible_videos(socket.assigns.entries), &(&1.id == video_id)) do
        assign(socket, :selected_video_id, video_id)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("close_video", _params, socket) do
    {:noreply, assign(socket, :selected_video_id, nil)}
  end

  def handle_event("next_image", _params, socket) do
    {:noreply, cycle_selected_image(socket, 1)}
  end

  def handle_event("prev_image", _params, socket) do
    {:noreply, cycle_selected_image(socket, -1)}
  end

  def handle_event("image_keydown", %{"key" => "ArrowRight"}, socket) do
    {:noreply, cycle_selected_image(socket, 1)}
  end

  def handle_event("image_keydown", %{"key" => "ArrowLeft"}, socket) do
    {:noreply, cycle_selected_image(socket, -1)}
  end

  def handle_event("image_keydown", %{"key" => "Escape"}, socket) do
    {:noreply, assign(socket, :selected_image_id, nil)}
  end

  def handle_event("image_keydown", _params, socket) do
    {:noreply, socket}
  end

  defp load_drive(socket, folder_id) do
    children = Drive.list_children(socket.assigns.current_scope, folder_id)

    socket
    |> assign(:page_title, "Drive")
    |> assign(:current_folder_id, folder_id && normalize_id(folder_id))
    |> assign(:children, children)
    |> assign(
      :breadcrumbs,
      Drive.list_breadcrumbs(socket.assigns.current_scope, folder_id && normalize_id(folder_id))
    )
    |> refresh_entries()
  end

  defp refresh_entries(socket) do
    controls = socket.assigns.controls
    children = socket.assigns.children

    entries =
      children
      |> build_entries()
      |> filter_entries(controls)
      |> sort_entries(controls["sort"])

    assign(socket,
      entries: entries,
      selected_entries:
        sanitize_selected_entries(entries, socket.assigns[:selected_entries] || MapSet.new()),
      selected_image_id: selected_image_id(entries, socket.assigns[:selected_image_id]),
      selected_video_id: selected_video_id(entries, socket.assigns[:selected_video_id]),
      workspace_used_size: Drive.workspace_used_size(socket.assigns.current_scope),
      folder_count: length(children.folders),
      file_count: length(children.files),
      total_size: Enum.reduce(children.files, 0, &(&1.file_object.size + &2))
    )
  end

  defp clear_rename_state(socket) do
    socket
    |> assign(:editing_file_id, nil)
    |> assign(:rename_form, to_form(%{"name" => ""}, as: "rename"))
  end

  defp editing_file(entries, editing_file_id) do
    Enum.find(entries, &(&1.kind == :file and &1.id == editing_file_id))
  end

  defp pending_delete_file(entries, pending_delete_file_id) do
    Enum.find(entries, &(&1.kind == :file and &1.id == pending_delete_file_id))
  end

  defp pending_delete_folder(entries, pending_delete_folder_id) do
    Enum.find(entries, &(&1.kind == :folder and &1.id == pending_delete_folder_id))
  end

  defp selected_entries(entries, selected_keys) do
    selected_keys = selected_keys || MapSet.new()
    Enum.filter(entries, &MapSet.member?(selected_keys, entry_selection_key(&1)))
  end

  defp selected_file_entries(entries, selected_keys) do
    Enum.filter(selected_entries(entries, selected_keys), &(&1.kind == :file))
  end

  defp assign_controls(socket, params) do
    controls =
      @default_controls
      |> Map.merge(socket.assigns.controls || %{})
      |> Map.merge(params)
      |> Map.update!("view", fn view -> if view in ["grid", "list"], do: view, else: "grid" end)
      |> Map.update!("type", fn type ->
        if type in ["all", "folders", "files", "images", "videos"], do: type, else: "all"
      end)
      |> Map.update!("sort", fn sort ->
        if sort in [
             "modified_desc",
             "modified_asc",
             "name_asc",
             "name_desc",
             "type_asc",
             "type_desc",
             "size_desc",
             "size_asc"
           ] do
          sort
        else
          "modified_desc"
        end
      end)

    socket
    |> assign(:controls, controls)
    |> assign(:controls_form, to_form(controls, as: "controls"))
  end

  defp build_entries(children) do
    folder_entries =
      Enum.map(children.folders, fn folder ->
        %{
          id: folder.id,
          kind: :folder,
          name: folder.name,
          content_type: "Folder",
          size: nil,
          updated_at: folder.updated_at,
          href: ~p"/app/folders/#{folder.id}",
          preview: :folder
        }
      end)

    file_entries =
      Enum.map(children.files, fn file ->
        %{
          id: file.id,
          kind: :file,
          name: file.name,
          content_type: file.file_object.content_type,
          size: file.file_object.size,
          updated_at: file.updated_at,
          href: ~p"/app/files/#{file.id}/download",
          preview:
            cond do
              image_file?(file) -> :image
              video_file?(file) -> :video
              true -> :file
            end
        }
      end)

    folder_entries ++ file_entries
  end

  defp filter_entries(entries, controls) do
    query = String.downcase(String.trim(controls["query"] || ""))
    type = controls["type"] || "all"

    Enum.filter(entries, fn entry ->
      matches_query? = query == "" or String.contains?(String.downcase(entry.name), query)

      matches_type? =
        case type do
          "all" -> true
          "folders" -> entry.kind == :folder
          "files" -> entry.kind == :file
          "images" -> entry.preview == :image
          "videos" -> entry.preview == :video
        end

      matches_query? and matches_type?
    end)
  end

  defp sort_entries(entries, "name_asc"),
    do: Enum.sort_by(entries, &{entry_order(&1), String.downcase(&1.name)})

  defp sort_entries(entries, "name_desc"),
    do: Enum.sort_by(entries, &{entry_order(&1), String.downcase(&1.name)}, :desc)

  defp sort_entries(entries, "type_asc"),
    do:
      Enum.sort_by(
        entries,
        &{entry_order(&1), String.downcase(&1.content_type || ""), String.downcase(&1.name)}
      )

  defp sort_entries(entries, "type_desc"),
    do:
      Enum.sort_by(
        entries,
        &{entry_order(&1), String.downcase(&1.content_type || ""), String.downcase(&1.name)},
        :desc
      )

  defp sort_entries(entries, "size_desc"),
    do: Enum.sort_by(entries, &{entry_order(&1), -(&1.size || -1), String.downcase(&1.name)})

  defp sort_entries(entries, "size_asc"),
    do: Enum.sort_by(entries, &{entry_order(&1), &1.size || -1, String.downcase(&1.name)})

  defp sort_entries(entries, "modified_asc") do
    Enum.sort(entries, fn left, right ->
      cond do
        entry_order(left) != entry_order(right) ->
          entry_order(left) <= entry_order(right)

        DateTime.compare(left.updated_at, right.updated_at) == :lt ->
          true

        DateTime.compare(left.updated_at, right.updated_at) == :gt ->
          false

        true ->
          String.downcase(left.name) <= String.downcase(right.name)
      end
    end)
  end

  defp sort_entries(entries, _sort) do
    Enum.sort(entries, fn left, right ->
      cond do
        entry_order(left) != entry_order(right) ->
          entry_order(left) <= entry_order(right)

        DateTime.compare(left.updated_at, right.updated_at) == :gt ->
          true

        DateTime.compare(left.updated_at, right.updated_at) == :lt ->
          false

        true ->
          String.downcase(left.name) <= String.downcase(right.name)
      end
    end)
  end

  defp entry_order(%{kind: :folder}), do: 0
  defp entry_order(%{kind: :file}), do: 1

  defp next_sort(current_sort, "name") when current_sort == "name_asc", do: "name_desc"
  defp next_sort(_current_sort, "name"), do: "name_asc"

  defp next_sort(current_sort, "type") when current_sort == "type_asc", do: "type_desc"
  defp next_sort(_current_sort, "type"), do: "type_asc"

  defp next_sort(current_sort, "modified") when current_sort == "modified_desc",
    do: "modified_asc"

  defp next_sort(_current_sort, "modified"), do: "modified_desc"

  defp next_sort(current_sort, "size") when current_sort == "size_desc", do: "size_asc"
  defp next_sort(_current_sort, "size"), do: "size_desc"

  defp sort_icon(sort, field) do
    case {field, sort} do
      {"name", "name_asc"} -> "hero-chevron-up"
      {"name", "name_desc"} -> "hero-chevron-down"
      {"type", "type_asc"} -> "hero-chevron-up"
      {"type", "type_desc"} -> "hero-chevron-down"
      {"modified", "modified_asc"} -> "hero-chevron-up"
      {"modified", "modified_desc"} -> "hero-chevron-down"
      {"size", "size_asc"} -> "hero-chevron-up"
      {"size", "size_desc"} -> "hero-chevron-down"
      _ -> "hero-chevron-up-down"
    end
  end

  defp active_sort?(sort, "name"), do: sort in ["name_asc", "name_desc"]
  defp active_sort?(sort, "type"), do: sort in ["type_asc", "type_desc"]
  defp active_sort?(sort, "modified"), do: sort in ["modified_asc", "modified_desc"]
  defp active_sort?(sort, "size"), do: sort in ["size_asc", "size_desc"]
  defp active_sort?(_sort, _field), do: false

  defp current_view(socket), do: socket.assigns.controls["view"] || "grid"

  defp visible_images(entries), do: Enum.filter(entries, &(&1.preview == :image))
  defp visible_videos(entries), do: Enum.filter(entries, &(&1.preview == :video))

  defp selected_image_id(entries, current_id) do
    if Enum.any?(entries, &(&1.preview == :image and &1.id == current_id)),
      do: current_id,
      else: nil
  end

  defp selected_image(entries, selected_image_id) do
    Enum.find(visible_images(entries), &(&1.id == selected_image_id))
  end

  defp selected_video_id(entries, current_id) do
    if Enum.any?(entries, &(&1.preview == :video and &1.id == current_id)),
      do: current_id,
      else: nil
  end

  defp selected_video(entries, selected_video_id) do
    Enum.find(visible_videos(entries), &(&1.id == selected_video_id))
  end

  defp visible_entry_keys(entries) do
    entries
    |> Enum.map(&entry_selection_key/1)
    |> MapSet.new()
  end

  defp sanitize_selected_entries(entries, selected_keys) do
    MapSet.intersection(selected_keys || MapSet.new(), visible_entry_keys(entries))
  end

  defp entry_selection_key(%{kind: kind, id: id}), do: "#{kind}:#{id}"

  defp selected_all_entries?(entries, selected_keys) do
    visible_keys = visible_entry_keys(entries)
    MapSet.size(visible_keys) > 0 and MapSet.equal?(visible_keys, selected_keys || MapSet.new())
  end

  defp bulk_delete_entries(_scope, []), do: {:error, :empty_selection}

  defp bulk_delete_entries(scope, entries) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      case Drive.soft_delete_node(scope, {entry.kind, entry.id}) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp cycle_selected_image(socket, step) do
    images = visible_images(socket.assigns.entries)

    case Enum.find_index(images, &(&1.id == socket.assigns.selected_image_id)) do
      nil ->
        socket

      index ->
        next_index = Integer.mod(index + step, length(images))
        assign(socket, :selected_image_id, Enum.at(images, next_index).id)
    end
  end

  defp normalize_id(id) when is_binary(id), do: String.to_integer(id)
  defp normalize_id(id), do: id

  defp image_file?(file), do: String.starts_with?(file.file_object.content_type || "", "image/")
  defp video_file?(file), do: String.starts_with?(file.file_object.content_type || "", "video/")

  defp format_bytes(bytes) when is_integer(bytes) and bytes < 1024, do: "#{bytes} B"

  defp format_bytes(bytes) when is_integer(bytes) and bytes < 1_048_576,
    do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_bytes(bytes) when is_integer(bytes) and bytes < 1_073_741_824,
    do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_bytes(bytes) when is_integer(bytes),
    do: "#{Float.round(bytes / 1_073_741_824, 1)} GB"

  defp format_bytes(_), do: "--"

  defp format_duration(seconds) when is_number(seconds) and seconds >= 0 do
    total_seconds = trunc(seconds)
    minutes = div(total_seconds, 60)
    remaining_seconds = rem(total_seconds, 60)

    "#{String.pad_leading(Integer.to_string(minutes), 2, "0")}:#{String.pad_leading(Integer.to_string(remaining_seconds), 2, "0")}"
  end

  defp format_duration(_), do: "--:--"

  defp relative_time(nil), do: "--"

  defp relative_time(datetime) do
    seconds = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      seconds < 60 -> "agora"
      seconds < 3600 -> "#{div(seconds, 60)} min"
      seconds < 86_400 -> "#{div(seconds, 3600)} h"
      true -> "#{div(seconds, 86_400)} d"
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:selected_image, selected_image(assigns.entries, assigns.selected_image_id))
      |> assign(:selected_video, selected_video(assigns.entries, assigns.selected_video_id))
      |> assign(:editing_file, editing_file(assigns.entries, assigns.editing_file_id))
      |> assign(
        :selected_list_entries,
        selected_entries(assigns.entries, assigns.selected_entries)
      )
      |> assign(
        :selected_file_entries,
        selected_file_entries(assigns.entries, assigns.selected_entries)
      )
      |> assign(
        :all_list_entries_selected,
        selected_all_entries?(assigns.entries, assigns.selected_entries)
      )
      |> assign(
        :pending_delete_folder,
        pending_delete_folder(assigns.entries, assigns.pending_delete_folder_id)
      )
      |> assign(
        :pending_delete_file,
        pending_delete_file(assigns.entries, assigns.pending_delete_file_id)
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="rounded-[2rem] border border-slate-200/80 bg-[linear-gradient(180deg,#f8fbff_0%,#f3f6fb_100%)] p-4 shadow-sm lg:p-6">
        <div class="grid gap-5 lg:grid-cols-[240px_minmax(0,1fr)]">
          <aside class="space-y-5 rounded-[1.75rem] bg-white/90 p-4 shadow-sm ring-1 ring-slate-200/70">
            <button
              phx-click="toggle_new_menu"
              class="flex w-full items-center justify-between rounded-2xl bg-slate-950 px-4 py-3 text-left text-sm font-semibold text-white shadow-sm transition hover:bg-slate-800"
            >
              <span class="flex items-center gap-3">
                <.icon name="hero-plus" class="size-5" /> Novo
              </span>
              <.icon
                name={if @new_menu_open, do: "hero-chevron-up", else: "hero-chevron-down"}
                class="size-4"
              />
            </button>

            <div
              :if={@new_menu_open}
              class="space-y-4 rounded-[1.5rem] bg-slate-50 p-3 ring-1 ring-slate-200"
            >
              <.form for={@folder_form} phx-submit="create_folder" class="space-y-2">
                <.input field={@folder_form[:name]} type="text" label="Nova pasta" required />
                <.button class="btn btn-primary w-full">Criar pasta</.button>
              </.form>
            </div>

            <nav class="space-y-1">
              <button
                phx-click="set_sidebar_preset"
                phx-value-preset="my_drive"
                class="flex w-full items-center gap-3 rounded-2xl px-3 py-2 text-sm font-medium text-slate-700 transition hover:bg-slate-100"
              >
                <.icon name="hero-home" class="size-5 text-slate-500" /> Meu Drive
              </button>
              <button
                phx-click="set_sidebar_preset"
                phx-value-preset="recent"
                class="flex w-full items-center gap-3 rounded-2xl px-3 py-2 text-sm text-slate-600 transition hover:bg-slate-100"
              >
                <.icon name="hero-clock" class="size-5 text-slate-500" /> Recentes
              </button>
              <button
                phx-click="set_sidebar_preset"
                phx-value-preset="images"
                class="flex w-full items-center gap-3 rounded-2xl px-3 py-2 text-sm text-slate-600 transition hover:bg-slate-100"
              >
                <.icon name="hero-photo" class="size-5 text-slate-500" /> Imagens
              </button>
              <button
                phx-click="set_sidebar_preset"
                phx-value-preset="videos"
                class="flex w-full items-center gap-3 rounded-2xl px-3 py-2 text-sm text-slate-600 transition hover:bg-slate-100"
              >
                <.icon name="hero-film" class="size-5 text-slate-500" /> Videos
              </button>
              <button
                phx-click="set_sidebar_preset"
                phx-value-preset="folders"
                class="flex w-full items-center gap-3 rounded-2xl px-3 py-2 text-sm text-slate-600 transition hover:bg-slate-100"
              >
                <.icon name="hero-folder" class="size-5 text-slate-500" /> Pastas
              </button>
              <.link
                navigate={~p"/app/trash"}
                class="flex items-center gap-3 rounded-2xl px-3 py-2 text-sm text-slate-600 transition hover:bg-slate-100"
              >
                <.icon name="hero-trash" class="size-5 text-slate-500" /> Lixeira
              </.link>
            </nav>

            <div class="rounded-[1.5rem] bg-slate-950 p-4 text-white">
              <p class="text-xs uppercase tracking-[0.28em] text-slate-400">Workspace</p>
              <p class="mt-2 text-lg font-semibold">{@current_scope.tenant.name}</p>
              <p class="mt-1 text-sm text-slate-400">{@current_scope.user.email}</p>
              <div class="mt-4 h-2 overflow-hidden rounded-full bg-slate-800">
                <div class="h-full w-full rounded-full bg-sky-400"></div>
              </div>
              <p class="mt-2 text-xs text-slate-400">
                {format_bytes(@workspace_used_size)} usados no workspace
              </p>
            </div>
          </aside>

          <div class="space-y-4">
            <header class="rounded-[1.75rem] bg-white/90 p-4 shadow-sm ring-1 ring-slate-200/70">
              <div class="flex flex-wrap items-center justify-between gap-4">
                <div>
                  <div class="flex items-center gap-2">
                    <h1 class="text-3xl font-black tracking-tight text-slate-950">Meu Drive</h1>
                    <.icon name="hero-chevron-down" class="size-4 text-slate-400" />
                  </div>
                  <nav class="mt-3 flex flex-wrap items-center gap-2 text-sm text-slate-500">
                    <.link navigate={~p"/app"} class="rounded-full bg-slate-100 px-3 py-1.5">
                      Root
                    </.link>
                    <%= for folder <- @breadcrumbs do %>
                      <span>/</span>
                      <.link
                        navigate={~p"/app/folders/#{folder.id}"}
                        class="rounded-full bg-slate-100 px-3 py-1.5"
                      >
                        {folder.name}
                      </.link>
                    <% end %>
                  </nav>
                </div>

                <div class="grid gap-2 sm:grid-cols-3">
                  <div class="rounded-2xl bg-slate-50 px-4 py-3 ring-1 ring-slate-200">
                    <p class="text-xs uppercase tracking-[0.2em] text-slate-400">Pastas</p>
                    <p class="mt-1 text-xl font-semibold text-slate-950">{@folder_count}</p>
                  </div>
                  <div class="rounded-2xl bg-slate-50 px-4 py-3 ring-1 ring-slate-200">
                    <p class="text-xs uppercase tracking-[0.2em] text-slate-400">Arquivos</p>
                    <p class="mt-1 text-xl font-semibold text-slate-950">{@file_count}</p>
                  </div>
                  <div class="rounded-2xl bg-slate-50 px-4 py-3 ring-1 ring-slate-200">
                    <p class="text-xs uppercase tracking-[0.2em] text-slate-400">Tamanho</p>
                    <p class="mt-1 text-xl font-semibold text-slate-950">
                      {format_bytes(@total_size)}
                    </p>
                  </div>
                </div>
              </div>
            </header>

            <section
              id="folder-dropzone"
              phx-hook="DirectUploadZone"
              data-initiate-url={~p"/app/uploads"}
              data-proxy-url={~p"/app/uploads/proxy"}
              data-complete-url={~p"/app/uploads/complete"}
              data-folder-id={@current_folder_id || ""}
              data-max-file-size={Drive.max_upload_file_size()}
              data-backend-fallback-size={Drive.backend_upload_fallback_size()}
              class="rounded-[1.75rem] bg-white/90 p-4 shadow-sm ring-1 ring-slate-200/70 transition phx-drop-target-active:bg-sky-50/80 phx-drop-target-active:ring-2 phx-drop-target-active:ring-sky-400"
            >
              <input
                id="folder-upload-input"
                data-direct-upload-input
                type="file"
                multiple
                class="hidden"
              />

              <div
                id="folder-upload-trigger"
                data-direct-upload-trigger
                role="button"
                tabindex="0"
                aria-label="Selecionar arquivos do dispositivo"
                class="mb-4 block cursor-pointer overflow-hidden rounded-[1.5rem] border border-dashed border-slate-200 bg-[linear-gradient(180deg,rgba(248,250,252,0.95),rgba(239,246,255,0.9))] px-4 py-5 text-center transition hover:border-sky-300 hover:bg-sky-50/70 focus:outline-none focus:ring-2 focus:ring-sky-400 focus:ring-offset-2"
              >
                <div class="flex flex-col items-center justify-center gap-3 sm:flex-row sm:text-left">
                  <div class="flex size-12 items-center justify-center rounded-2xl bg-white text-sky-600 shadow-sm ring-1 ring-sky-100">
                    <.icon name="hero-arrow-up-tray" class="size-6" />
                  </div>
                  <div>
                    <p class="text-sm font-semibold text-slate-900">
                      Arraste arquivos para esta pasta
                    </p>
                    <p class="mt-1 text-xs text-slate-500">
                      O upload comeca assim que voce solta o arquivo
                    </p>
                    <p class="mt-1 text-xs text-slate-400">
                      Voce pode soltar varios arquivos por vez
                    </p>
                    <p class="mt-2 text-[11px] uppercase tracking-[0.18em] text-slate-400">
                      Clique para escolher arquivos do dispositivo
                    </p>
                  </div>
                </div>
              </div>

              <div
                id="direct-upload-queue"
                data-direct-upload-queue
                phx-update="ignore"
                class="mb-4 overflow-hidden rounded-[1.5rem] bg-white shadow-sm ring-1 ring-slate-200"
                hidden
              >
                <div class="flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 bg-slate-50/80 px-4 py-3">
                  <div>
                    <p class="text-sm font-semibold text-slate-900">Fila de uploads</p>
                    <p class="text-xs text-slate-500">
                      Acompanhe o progresso de cada arquivo em tempo real
                    </p>
                  </div>
                  <div class="flex flex-wrap items-center gap-2 text-[11px] font-medium">
                    <span
                      data-upload-stat="queued"
                      class="rounded-full bg-slate-100 px-3 py-1 text-slate-600 ring-1 ring-slate-200"
                    >
                      0 na fila
                    </span>
                    <span
                      data-upload-stat="uploading"
                      class="rounded-full bg-sky-100 px-3 py-1 text-sky-700 ring-1 ring-sky-200"
                    >
                      0 enviando
                    </span>
                    <span
                      data-upload-stat="complete"
                      class="rounded-full bg-emerald-100 px-3 py-1 text-emerald-700 ring-1 ring-emerald-200"
                    >
                      0 concluidos
                    </span>
                    <span
                      data-upload-stat="error"
                      class="rounded-full bg-rose-100 px-3 py-1 text-rose-700 ring-1 ring-rose-200"
                    >
                      0 com erro
                    </span>
                  </div>
                </div>

                <div data-direct-upload-entries></div>
              </div>

              <div
                id="direct-upload-errors"
                data-direct-upload-errors
                phx-update="ignore"
                class="mb-4 rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3 text-xs text-amber-800"
                hidden
              >
              </div>

              <.form
                for={@controls_form}
                id="controls_form"
                phx-change="update_controls"
                class="flex flex-wrap items-center gap-3"
              >
                <label class="flex min-w-[220px] flex-1 items-center gap-3 rounded-2xl bg-slate-100 px-4 py-3">
                  <.icon name="hero-magnifying-glass" class="size-5 text-slate-400" />
                  <input
                    type="text"
                    name={@controls_form[:query].name}
                    value={@controls_form[:query].value}
                    placeholder="Buscar por nome"
                    class="w-full bg-transparent text-sm outline-none placeholder:text-slate-400"
                  />
                </label>

                <.input
                  field={@controls_form[:type]}
                  type="select"
                  options={[
                    {"Tudo", "all"},
                    {"Pastas", "folders"},
                    {"Arquivos", "files"},
                    {"Imagens", "images"},
                    {"Videos", "videos"}
                  ]}
                  class="select rounded-2xl bg-slate-100 px-4"
                />

                <.input
                  field={@controls_form[:sort]}
                  type="select"
                  options={[
                    {"Modificado", "modified_desc"},
                    {"Modificado mais antigo", "modified_asc"},
                    {"Nome", "name_asc"},
                    {"Nome Z-A", "name_desc"},
                    {"Tipo", "type_asc"},
                    {"Tipo Z-A", "type_desc"},
                    {"Maior tamanho", "size_desc"},
                    {"Menor tamanho", "size_asc"}
                  ]}
                  class="select rounded-2xl bg-slate-100 px-4"
                />

                <input
                  type="hidden"
                  name={@controls_form[:view].name}
                  value={@controls_form[:view].value}
                />
              </.form>

              <div class="mt-4 flex items-center justify-between gap-3 border-t border-slate-200 pt-4">
                <div class="flex items-center gap-2 text-sm text-slate-500">
                  <span class="rounded-full bg-slate-100 px-3 py-1.5">
                    {length(@entries)} resultados
                  </span>
                  <span
                    :if={@controls["type"] != "all"}
                    class="rounded-full bg-sky-50 px-3 py-1.5 text-sky-700"
                  >
                    filtro: {@controls["type"]}
                  </span>
                </div>

                <div class="inline-flex rounded-2xl bg-slate-100 p-1">
                  <button
                    phx-click="set_view"
                    phx-value-view="grid"
                    class={[
                      "rounded-xl px-3 py-2 text-sm transition",
                      @controls["view"] == "grid" && "bg-white shadow-sm text-slate-950",
                      @controls["view"] != "grid" && "text-slate-500"
                    ]}
                  >
                    <.icon name="hero-squares-2x2" class="size-5" />
                  </button>
                  <button
                    phx-click="set_view"
                    phx-value-view="list"
                    class={[
                      "rounded-xl px-3 py-2 text-sm transition",
                      @controls["view"] == "list" && "bg-white shadow-sm text-slate-950",
                      @controls["view"] != "list" && "text-slate-500"
                    ]}
                  >
                    <.icon name="hero-list-bullet" class="size-5" />
                  </button>
                </div>
              </div>
            </section>

            <section
              :if={@entries == []}
              class="rounded-[1.75rem] border border-dashed border-slate-300 bg-white/80 px-8 py-16 text-center"
            >
              <div class="mx-auto flex size-16 items-center justify-center rounded-full bg-slate-100">
                <.icon name="hero-folder-open" class="size-8 text-slate-400" />
              </div>
              <h2 class="mt-5 text-2xl font-semibold text-slate-950">Nada por aqui ainda</h2>
              <p class="mt-2 text-sm text-slate-500">
                Crie uma pasta, envie um arquivo ou ajuste os filtros para encontrar o que precisa.
              </p>
            </section>

            <section
              :if={@entries != [] and @controls["view"] == "grid"}
              class="grid gap-4 sm:grid-cols-2 xl:grid-cols-3"
            >
              <%= for entry <- @entries do %>
                <article class="overflow-hidden rounded-[1.5rem] bg-white shadow-sm ring-1 ring-slate-200 transition hover:-translate-y-0.5 hover:shadow-md">
                  <div class="flex items-center justify-between border-b border-slate-100 px-4 py-3">
                    <div class="flex min-w-0 items-center gap-3">
                      <div class={[
                        "flex size-10 items-center justify-center rounded-2xl",
                        entry.kind == :folder && "bg-sky-100 text-sky-700",
                        entry.kind == :file && "bg-slate-100 text-slate-700"
                      ]}>
                        <.icon
                          name={
                            case entry.preview do
                              :folder -> "hero-folder"
                              :image -> "hero-photo"
                              :video -> "hero-film"
                              :file -> "hero-document"
                            end
                          }
                          class="size-5"
                        />
                      </div>
                      <div class="min-w-0">
                        <p class="truncate text-sm font-semibold text-slate-950">{entry.name}</p>
                        <p class="text-xs text-slate-400">{relative_time(entry.updated_at)}</p>
                      </div>
                    </div>
                    <button
                      :if={entry.kind == :folder}
                      phx-click="delete_folder"
                      phx-value-id={entry.id}
                      class="rounded-lg p-2 text-slate-400 transition hover:bg-slate-100 hover:text-rose-500"
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                    <button
                      :if={entry.kind == :file}
                      phx-click="start_rename_file"
                      phx-value-id={entry.id}
                      class="rounded-lg p-2 text-slate-400 transition hover:bg-slate-100 hover:text-sky-600"
                    >
                      <.icon name="hero-pencil-square" class="size-4" />
                    </button>
                    <button
                      :if={entry.kind == :file}
                      type="button"
                      phx-click="delete_file"
                      phx-value-id={entry.id}
                      class="rounded-lg p-2 text-slate-400 transition hover:bg-slate-100 hover:text-rose-500"
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                  </div>

                  <div class="bg-[linear-gradient(180deg,#f8fafc_0%,#eef3f8_100%)] p-4">
                    <.link
                      :if={entry.kind == :folder}
                      navigate={entry.href}
                      class="flex h-36 items-center justify-center rounded-[1.25rem] border border-dashed border-slate-300 text-slate-500"
                    >
                      <div class="text-center">
                        <.icon name="hero-folder" class="mx-auto size-10 text-sky-600" />
                        <p class="mt-2 text-sm font-medium">Abrir pasta</p>
                      </div>
                    </.link>

                    <button
                      :if={entry.preview == :image}
                      type="button"
                      phx-click="open_image"
                      phx-value-id={entry.id}
                      class="block w-full overflow-hidden rounded-[1.25rem] ring-1 ring-slate-200 transition hover:ring-sky-300"
                    >
                      <img
                        src={entry.href}
                        alt={entry.name}
                        class="h-36 w-full object-cover"
                      />
                    </button>

                    <button
                      :if={entry.preview == :video}
                      type="button"
                      phx-click="open_video"
                      phx-value-id={entry.id}
                      class="video-preview-shell group relative block h-36 w-full overflow-hidden rounded-[1.25rem] text-left ring-1 ring-slate-200 transition hover:ring-sky-300 focus:outline-none focus:ring-2 focus:ring-sky-400 focus:ring-offset-2"
                      aria-label={"Abrir video #{entry.name}"}
                    >
                      <video
                        src={entry.href}
                        preload="metadata"
                        muted
                        playsinline
                        class="h-full w-full object-cover"
                      />
                      <div class="video-preview-overlay pointer-events-none absolute inset-0"></div>

                      <div class="pointer-events-none absolute inset-x-0 top-0 flex items-start justify-between p-3">
                        <span class="rounded-full border border-white/20 bg-slate-950/55 px-2.5 py-1 text-[10px] font-semibold uppercase tracking-[0.24em] text-white/80 backdrop-blur-md">
                          Video
                        </span>
                        <span class="rounded-full border border-white/15 bg-white/12 px-2.5 py-1 text-[11px] font-medium text-white/85 shadow-sm backdrop-blur-md">
                          Abrir player
                        </span>
                      </div>

                      <div class="absolute inset-0 flex items-center justify-center">
                        <div class="video-preview-play flex size-14 items-center justify-center rounded-full border border-white/20 bg-white/18 text-white shadow-[0_18px_45px_rgba(15,23,42,0.35)] backdrop-blur-xl transition duration-300 group-hover:scale-105 group-hover:bg-white/24">
                          <svg
                            viewBox="0 0 24 24"
                            fill="currentColor"
                            class="ml-1 size-6"
                            aria-hidden="true"
                          >
                            <path d="M8 6.82v10.36c0 .79.87 1.26 1.54.84l8.17-5.18a1 1 0 0 0 0-1.69L9.54 5.98A1 1 0 0 0 8 6.82Z" />
                          </svg>
                        </div>
                      </div>
                    </button>

                    <div
                      :if={entry.preview == :file}
                      class="flex h-36 items-center justify-center rounded-[1.25rem] border border-dashed border-slate-300 bg-white text-slate-500"
                    >
                      <div class="text-center">
                        <.icon name="hero-document" class="mx-auto size-10" />
                        <p class="mt-2 text-sm">{entry.content_type || "Arquivo"}</p>
                      </div>
                    </div>
                  </div>

                  <div class="flex items-center justify-between px-4 py-3 text-sm">
                    <div>
                      <p class="text-slate-500">{entry.content_type}</p>
                      <p :if={entry.kind == :file} class="text-xs text-slate-400">
                        {format_bytes(entry.size)}
                      </p>
                    </div>
                    <.link
                      :if={entry.kind == :file}
                      href={entry.href}
                      class="rounded-xl bg-slate-100 px-3 py-2 font-medium text-slate-700 transition hover:bg-slate-200"
                    >
                      Baixar
                    </.link>
                  </div>
                </article>
              <% end %>
            </section>

            <section
              :if={@entries != [] and @controls["view"] == "list"}
              id="drive-list-view"
              phx-hook="ResizableListColumns"
              data-storage-key={"drive-list-columns-#{@current_scope.tenant.id}"}
              class="overflow-hidden rounded-[1.75rem] bg-white shadow-sm ring-1 ring-slate-200/70"
            >
              <div class="flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 bg-slate-50/70 px-5 py-3">
                <div class="flex flex-wrap items-center gap-3 text-sm text-slate-500">
                  <label class="flex items-center gap-2 rounded-full bg-white px-3 py-2 ring-1 ring-slate-200">
                    <input
                      type="checkbox"
                      phx-click="toggle_all_entries"
                      phx-value-state={
                        if @all_list_entries_selected, do: "unchecked", else: "checked"
                      }
                      checked={@all_list_entries_selected}
                      class="checkbox checkbox-sm rounded-md border-slate-300"
                    />
                    <span>Selecionar todos</span>
                  </label>
                  <span class="rounded-full bg-white px-3 py-2 ring-1 ring-slate-200">
                    Selecionados: {length(@selected_list_entries)}
                  </span>
                  <span
                    :if={@selected_file_entries != []}
                    class="rounded-full bg-sky-50 px-3 py-2 text-sky-700 ring-1 ring-sky-200"
                  >
                    {length(@selected_file_entries)} arquivo(s) para ZIP
                  </span>
                </div>

                <div class="flex flex-wrap items-center gap-2">
                  <form method="post" action={~p"/app/files/download-zip"}>
                    <input
                      type="hidden"
                      name="_csrf_token"
                      value={Phoenix.Controller.get_csrf_token()}
                    />
                    <%= for entry <- @selected_file_entries do %>
                      <input type="hidden" name="file_ids[]" value={entry.id} />
                    <% end %>
                    <button
                      type="submit"
                      disabled={@selected_file_entries == []}
                      class="rounded-xl bg-sky-600 px-4 py-2.5 text-sm font-semibold text-white transition enabled:hover:bg-sky-700 disabled:cursor-not-allowed disabled:bg-slate-200 disabled:text-slate-400"
                    >
                      Baixar ZIP
                    </button>
                  </form>

                  <button
                    type="button"
                    phx-click="open_bulk_delete_modal"
                    disabled={@selected_list_entries == []}
                    class="rounded-xl bg-rose-600 px-4 py-2.5 text-sm font-semibold text-white transition enabled:hover:bg-rose-700 disabled:cursor-not-allowed disabled:bg-slate-200 disabled:text-slate-400"
                  >
                    Deletar selecionados
                  </button>
                </div>
              </div>

              <div class="drive-list-grid gap-4 border-b border-slate-200 px-5 py-3 text-xs font-semibold uppercase tracking-[0.2em] text-slate-400">
                <span class="flex items-center justify-center">Sel.</span>
                <div class="drive-list-header-cell" data-resizable-column="name">
                  <button
                    type="button"
                    phx-click="toggle_sort"
                    phx-value-field="name"
                    class={[
                      "drive-list-header-button flex min-w-0 items-center gap-2 text-left transition hover:text-slate-700",
                      active_sort?(@controls["sort"], "name") && "text-slate-700"
                    ]}
                  >
                    <span>Nome</span>
                    <.icon name={sort_icon(@controls["sort"], "name")} class="size-4" />
                  </button>
                  <button
                    type="button"
                    class="drive-list-resizer"
                    data-column-resizer="name"
                    data-min-width="260"
                    data-max-width="820"
                    aria-label="Redimensionar coluna Nome"
                  >
                  </button>
                </div>
                <div class="drive-list-header-cell" data-resizable-column="type">
                  <button
                    type="button"
                    phx-click="toggle_sort"
                    phx-value-field="type"
                    class={[
                      "drive-list-header-button flex min-w-0 items-center gap-2 text-left transition hover:text-slate-700",
                      active_sort?(@controls["sort"], "type") && "text-slate-700"
                    ]}
                  >
                    <span>Tipo</span>
                    <.icon name={sort_icon(@controls["sort"], "type")} class="size-4" />
                  </button>
                  <button
                    type="button"
                    class="drive-list-resizer"
                    data-column-resizer="type"
                    data-min-width="120"
                    data-max-width="320"
                    aria-label="Redimensionar coluna Tipo"
                  >
                  </button>
                </div>
                <div class="drive-list-header-cell" data-resizable-column="modified">
                  <button
                    type="button"
                    phx-click="toggle_sort"
                    phx-value-field="modified"
                    class={[
                      "drive-list-header-button flex min-w-0 items-center gap-2 text-left transition hover:text-slate-700",
                      active_sort?(@controls["sort"], "modified") && "text-slate-700"
                    ]}
                  >
                    <span>Modificado</span>
                    <.icon name={sort_icon(@controls["sort"], "modified")} class="size-4" />
                  </button>
                  <button
                    type="button"
                    class="drive-list-resizer"
                    data-column-resizer="modified"
                    data-min-width="110"
                    data-max-width="280"
                    aria-label="Redimensionar coluna Modificado"
                  >
                  </button>
                </div>
                <div class="drive-list-header-cell" data-resizable-column="size">
                  <button
                    type="button"
                    phx-click="toggle_sort"
                    phx-value-field="size"
                    class={[
                      "drive-list-header-button flex min-w-0 items-center gap-2 text-left transition hover:text-slate-700",
                      active_sort?(@controls["sort"], "size") && "text-slate-700"
                    ]}
                  >
                    <span>Tamanho</span>
                    <.icon name={sort_icon(@controls["sort"], "size")} class="size-4" />
                  </button>
                  <button
                    type="button"
                    class="drive-list-resizer"
                    data-column-resizer="size"
                    data-min-width="110"
                    data-max-width="280"
                    aria-label="Redimensionar coluna Tamanho"
                  >
                  </button>
                </div>
                <span></span>
              </div>

              <%= for entry <- @entries do %>
                <div class="drive-list-grid items-center gap-4 border-b border-slate-100 px-5 py-3 last:border-b-0">
                  <label class="flex items-center justify-center">
                    <input
                      type="checkbox"
                      phx-click="toggle_entry_selection"
                      phx-value-key={entry_selection_key(entry)}
                      checked={MapSet.member?(@selected_entries, entry_selection_key(entry))}
                      class="checkbox checkbox-sm rounded-md border-slate-300"
                    />
                  </label>
                  <div class="flex min-w-0 overflow-hidden items-center gap-3">
                    <div class={[
                      "flex size-10 shrink-0 items-center justify-center rounded-2xl",
                      entry.kind == :folder && "bg-sky-100 text-sky-700",
                      entry.kind == :file && "bg-slate-100 text-slate-700"
                    ]}>
                      <.icon
                        name={
                          case entry.preview do
                            :folder -> "hero-folder"
                            :image -> "hero-photo"
                            :video -> "hero-film"
                            :file -> "hero-document"
                          end
                        }
                        class="size-5"
                      />
                    </div>

                    <div class="min-w-0 overflow-hidden">
                      <.link
                        :if={entry.kind == :folder}
                        navigate={entry.href}
                        class="block w-full truncate whitespace-nowrap font-medium text-slate-950 hover:text-sky-700"
                      >
                        {entry.name}
                      </.link>
                      <.link
                        :if={entry.kind == :file and entry.preview not in [:image, :video]}
                        href={entry.href}
                        class="block w-full truncate whitespace-nowrap font-medium text-slate-950 hover:text-sky-700"
                      >
                        {entry.name}
                      </.link>
                      <button
                        :if={entry.preview == :image}
                        type="button"
                        phx-click="open_image"
                        phx-value-id={entry.id}
                        class="block w-full truncate whitespace-nowrap text-left font-medium text-slate-950 hover:text-sky-700"
                      >
                        {entry.name}
                      </button>
                      <button
                        :if={entry.preview == :video}
                        type="button"
                        phx-click="open_video"
                        phx-value-id={entry.id}
                        class="block w-full truncate whitespace-nowrap text-left font-medium text-slate-950 hover:text-sky-700"
                      >
                        {entry.name}
                      </button>
                    </div>
                  </div>
                  <span class="min-w-0 truncate text-sm text-slate-500">{entry.content_type}</span>
                  <span class="min-w-0 truncate text-sm text-slate-500">
                    {relative_time(entry.updated_at)}
                  </span>
                  <span class="min-w-0 truncate text-sm text-slate-500">
                    {format_bytes(entry.size)}
                  </span>
                  <div class="flex items-center justify-end gap-2">
                    <.link
                      :if={entry.kind == :file}
                      href={entry.href}
                      class="rounded-xl bg-slate-100 px-3 py-2 text-sm text-slate-700 hover:bg-slate-200"
                    >
                      Baixar
                    </.link>
                    <button
                      :if={entry.kind == :folder}
                      phx-click="delete_folder"
                      phx-value-id={entry.id}
                      class="rounded-lg p-2 text-slate-400 hover:bg-slate-100 hover:text-rose-500"
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                    <button
                      :if={entry.kind == :file}
                      phx-click="start_rename_file"
                      phx-value-id={entry.id}
                      class="rounded-lg p-2 text-slate-400 hover:bg-slate-100 hover:text-sky-600"
                    >
                      <.icon name="hero-pencil-square" class="size-4" />
                    </button>
                    <button
                      :if={entry.kind == :file}
                      type="button"
                      phx-click="delete_file"
                      phx-value-id={entry.id}
                      class="rounded-lg p-2 text-slate-400 hover:bg-slate-100 hover:text-rose-500"
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                  </div>
                </div>
              <% end %>
            </section>

            <%= if selected = @editing_file do %>
              <div class="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/70 p-4">
                <button
                  type="button"
                  phx-click="cancel_rename_file"
                  class="absolute inset-0 cursor-default"
                  aria-label="Fechar modal de renomear arquivo"
                >
                </button>

                <div class="relative z-10 w-full max-w-xl overflow-hidden rounded-[2rem] bg-white shadow-2xl ring-1 ring-slate-200">
                  <div class="border-b border-slate-200 px-6 py-5">
                    <p class="text-xs font-semibold uppercase tracking-[0.24em] text-sky-600">
                      Renomear arquivo
                    </p>
                    <h2 class="mt-2 text-2xl font-bold tracking-tight text-slate-950">
                      {selected.name}
                    </h2>
                    <p class="mt-2 text-sm text-slate-500">
                      O nome sera atualizado no Drive e a key do arquivo sera movida no S3.
                    </p>
                  </div>

                  <.form for={@rename_form} phx-submit="rename_file" class="space-y-5 px-6 py-6">
                    <input type="hidden" name="file_id" value={selected.id} />

                    <div>
                      <label class="block text-sm font-medium text-slate-700">Novo nome</label>
                      <input
                        type="text"
                        name={@rename_form[:name].name}
                        value={@rename_form[:name].value}
                        class="mt-2 w-full rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-base text-slate-950 outline-none transition focus:border-sky-300 focus:bg-white focus:ring-2 focus:ring-sky-200"
                        required
                        autofocus
                      />
                    </div>

                    <div class="rounded-2xl bg-slate-50 px-4 py-3 text-sm text-slate-500 ring-1 ring-slate-200">
                      {selected.content_type} · {format_bytes(selected.size)}
                    </div>

                    <div class="flex items-center justify-end gap-3">
                      <button
                        type="button"
                        phx-click="cancel_rename_file"
                        class="rounded-xl px-4 py-2.5 text-sm font-medium text-slate-500 transition hover:bg-slate-100"
                      >
                        Cancelar
                      </button>
                      <button
                        type="submit"
                        class="rounded-xl bg-slate-950 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-slate-800"
                      >
                        Salvar
                      </button>
                    </div>
                  </.form>
                </div>
              </div>
            <% end %>

            <%= if selected = @pending_delete_file do %>
              <div class="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/70 p-4">
                <button
                  type="button"
                  phx-click="cancel_delete_file"
                  class="absolute inset-0 cursor-default"
                  aria-label="Fechar modal de exclusao de arquivo"
                >
                </button>

                <div class="relative z-10 w-full max-w-lg overflow-hidden rounded-[2rem] bg-white shadow-2xl ring-1 ring-slate-200">
                  <div class="border-b border-slate-200 px-6 py-5">
                    <p class="text-xs font-semibold uppercase tracking-[0.24em] text-rose-600">
                      Deletar arquivo
                    </p>
                    <h2 class="mt-2 text-2xl font-bold tracking-tight text-slate-950">
                      Tem certeza?
                    </h2>
                    <p class="mt-2 text-sm text-slate-500">
                      O arquivo <span class="font-semibold text-slate-700">{selected.name}</span>
                      sera enviado para a lixeira.
                    </p>
                  </div>

                  <div class="space-y-5 px-6 py-6">
                    <div class="rounded-2xl bg-slate-50 px-4 py-3 text-sm text-slate-500 ring-1 ring-slate-200">
                      {selected.content_type} · {format_bytes(selected.size)}
                    </div>

                    <div class="flex items-center justify-end gap-3">
                      <button
                        type="button"
                        phx-click="cancel_delete_file"
                        class="rounded-xl px-4 py-2.5 text-sm font-medium text-slate-500 transition hover:bg-slate-100"
                      >
                        Cancelar
                      </button>
                      <button
                        type="button"
                        phx-click="confirm_delete_file"
                        phx-value-id={selected.id}
                        class="rounded-xl bg-rose-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-rose-700"
                      >
                        Deletar
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>

            <%= if selected = @pending_delete_folder do %>
              <div class="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/70 p-4">
                <button
                  type="button"
                  phx-click="cancel_delete_folder"
                  class="absolute inset-0 cursor-default"
                  aria-label="Fechar modal de exclusao de pasta"
                >
                </button>

                <div class="relative z-10 w-full max-w-lg overflow-hidden rounded-[2rem] bg-white shadow-2xl ring-1 ring-slate-200">
                  <div class="border-b border-slate-200 px-6 py-5">
                    <p class="text-xs font-semibold uppercase tracking-[0.24em] text-rose-600">
                      Deletar pasta
                    </p>
                    <h2 class="mt-2 text-2xl font-bold tracking-tight text-slate-950">
                      Tem certeza?
                    </h2>
                    <p class="mt-2 text-sm text-slate-500">
                      A pasta <span class="font-semibold text-slate-700">{selected.name}</span>
                      sera enviada para a lixeira.
                    </p>
                  </div>

                  <div class="space-y-5 px-6 py-6">
                    <div class="rounded-2xl bg-slate-50 px-4 py-3 text-sm text-slate-500 ring-1 ring-slate-200">
                      Os itens dentro desta pasta tambem deixarao de aparecer no Drive atual.
                    </div>

                    <div class="flex items-center justify-end gap-3">
                      <button
                        type="button"
                        phx-click="cancel_delete_folder"
                        class="rounded-xl px-4 py-2.5 text-sm font-medium text-slate-500 transition hover:bg-slate-100"
                      >
                        Cancelar
                      </button>
                      <button
                        type="button"
                        phx-click="confirm_delete_folder"
                        phx-value-id={selected.id}
                        class="rounded-xl bg-rose-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-rose-700"
                      >
                        Deletar
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>

            <%= if @confirm_bulk_delete do %>
              <div class="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/70 p-4">
                <button
                  type="button"
                  phx-click="cancel_bulk_delete"
                  class="absolute inset-0 cursor-default"
                  aria-label="Fechar modal de exclusao em massa"
                >
                </button>

                <div class="relative z-10 w-full max-w-lg overflow-hidden rounded-[2rem] bg-white shadow-2xl ring-1 ring-slate-200">
                  <div class="border-b border-slate-200 px-6 py-5">
                    <p class="text-xs font-semibold uppercase tracking-[0.24em] text-rose-600">
                      Deletar em massa
                    </p>
                    <h2 class="mt-2 text-2xl font-bold tracking-tight text-slate-950">
                      Confirmar exclusao
                    </h2>
                    <p class="mt-2 text-sm text-slate-500">
                      {length(@selected_list_entries)} item(ns) selecionado(s) sera(ao) enviado(s) para a lixeira.
                    </p>
                  </div>

                  <div class="space-y-5 px-6 py-6">
                    <div class="max-h-56 space-y-2 overflow-y-auto rounded-2xl bg-slate-50 px-4 py-3 text-sm text-slate-600 ring-1 ring-slate-200">
                      <%= for entry <- @selected_list_entries do %>
                        <p>{entry.name}</p>
                      <% end %>
                    </div>

                    <div class="flex items-center justify-end gap-3">
                      <button
                        type="button"
                        phx-click="cancel_bulk_delete"
                        class="rounded-xl px-4 py-2.5 text-sm font-medium text-slate-500 transition hover:bg-slate-100"
                      >
                        Cancelar
                      </button>
                      <button
                        type="button"
                        phx-click="confirm_bulk_delete"
                        class="rounded-xl bg-rose-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-rose-700"
                      >
                        Deletar selecionados
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>

            <%= if selected = @selected_image do %>
              <div
                class="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/80 p-4"
                phx-window-keydown="image_keydown"
              >
                <button
                  type="button"
                  phx-click="close_image"
                  class="absolute inset-0 cursor-default"
                  aria-label="Fechar visualizacao"
                >
                </button>

                <div class="relative z-10 w-full max-w-5xl overflow-hidden rounded-[2rem] bg-slate-950 text-white shadow-2xl">
                  <div class="flex items-center justify-between border-b border-white/10 px-5 py-4">
                    <div class="min-w-0">
                      <p class="truncate text-base font-semibold">{selected.name}</p>
                      <p class="text-sm text-slate-400">{format_bytes(selected.size)}</p>
                    </div>

                    <button
                      type="button"
                      phx-click="close_image"
                      class="rounded-full border border-white/15 p-2 text-white transition hover:bg-white/10"
                      aria-label="Fechar"
                    >
                      <.icon name="hero-x-mark" class="size-5" />
                    </button>
                  </div>

                  <div class="relative bg-[radial-gradient(circle_at_top,#1e293b_0%,#020617_65%)] p-4 sm:p-6">
                    <button
                      type="button"
                      phx-click="prev_image"
                      class="absolute left-6 top-1/2 z-20 -translate-y-1/2 rounded-full bg-slate-950/70 p-3 text-white shadow-lg ring-1 ring-white/15 transition hover:bg-slate-900"
                      aria-label="Foto anterior"
                    >
                      <.icon name="hero-chevron-left" class="size-6" />
                    </button>

                    <button
                      type="button"
                      phx-click="next_image"
                      class="absolute right-6 top-1/2 z-20 -translate-y-1/2 rounded-full bg-slate-950/70 p-3 text-white shadow-lg ring-1 ring-white/15 transition hover:bg-slate-900"
                      aria-label="Proxima foto"
                    >
                      <.icon name="hero-chevron-right" class="size-6" />
                    </button>

                    <img
                      src={selected.href}
                      alt={selected.name}
                      class="max-h-[75vh] w-full rounded-[1.5rem] object-contain"
                    />
                  </div>
                </div>
              </div>
            <% end %>

            <%= if selected = @selected_video do %>
              <div class="fixed inset-0 z-50 flex items-center justify-center bg-[radial-gradient(circle_at_top,#111827_0%,#020617_68%)] p-4 sm:p-6">
                <button
                  type="button"
                  phx-click="close_video"
                  class="absolute inset-0 cursor-default"
                  aria-label="Fechar player de video"
                >
                </button>

                <div class="relative z-10 w-full max-w-[96rem] rounded-[2rem] border border-white/10 bg-[#060b1c]/95 p-4 text-white shadow-[0_32px_120px_rgba(2,6,23,0.7)] ring-1 ring-sky-500/10 sm:p-6">
                  <div class="flex items-center justify-between border-b border-white/10 px-5 py-4">
                    <div class="min-w-0">
                      <p class="truncate text-base font-semibold">{selected.name}</p>
                      <p class="text-sm text-slate-400">
                        {selected.content_type} · {format_bytes(selected.size)}
                      </p>
                    </div>

                    <button
                      type="button"
                      phx-click="close_video"
                      class="rounded-full border border-white/15 p-2 text-white transition hover:bg-white/10"
                      aria-label="Fechar"
                    >
                      <.icon name="hero-x-mark" class="size-5" />
                    </button>
                  </div>

                  <div class="grid gap-5 bg-[radial-gradient(circle_at_top,#111827_0%,#030712_72%)] pt-4 lg:grid-cols-[minmax(0,1fr)_310px] lg:items-start">
                    <div
                      id={"video-modal-#{selected.id}"}
                      phx-hook="VideoPreview"
                      data-video-player
                      data-autoplay="true"
                      data-shortcuts="true"
                      class="video-preview-shell group relative overflow-hidden rounded-[1.75rem] border border-white/10 p-3 shadow-[inset_0_1px_0_rgba(255,255,255,0.03)]"
                    >
                      <div class="relative overflow-hidden rounded-[1.4rem] bg-black">
                        <div class="aspect-video">
                          <video
                            src={selected.href}
                            preload="metadata"
                            playsinline
                            class="h-full w-full object-contain"
                          />
                        </div>

                        <div class="video-preview-overlay pointer-events-none absolute inset-0"></div>

                        <div class="pointer-events-none absolute inset-x-0 top-0 flex items-start justify-between p-4">
                          <div>
                            <span class="inline-flex rounded-full border border-white/15 bg-slate-950/55 px-3 py-1 text-[10px] font-semibold uppercase tracking-[0.28em] text-white/75 backdrop-blur-md">
                              OpenDrive Player
                            </span>
                            <p class="mt-3 text-xs text-white/45">
                              Velocidade <span data-role="speed">1x</span>
                            </p>
                          </div>
                          <span
                            data-role="duration"
                            class="rounded-full border border-white/15 bg-white/12 px-3 py-1 text-[11px] font-medium text-white/85 shadow-sm backdrop-blur-md"
                          >
                            {format_duration(0)}
                          </span>
                        </div>

                        <div class="absolute inset-0 flex items-center justify-center">
                          <button
                            type="button"
                            data-action="toggle-play"
                            class="video-preview-play flex size-20 items-center justify-center rounded-full border border-white/20 bg-white/18 text-white shadow-[0_18px_45px_rgba(15,23,42,0.35)] backdrop-blur-xl transition duration-300 hover:scale-105 hover:bg-white/24 focus:outline-none focus:ring-2 focus:ring-white/80 focus:ring-offset-2 focus:ring-offset-slate-950"
                            aria-label="Reproduzir video"
                          >
                            <svg
                              data-icon="play"
                              viewBox="0 0 24 24"
                              fill="currentColor"
                              class="ml-1 size-8"
                              aria-hidden="true"
                            >
                              <path d="M8 6.82v10.36c0 .79.87 1.26 1.54.84l8.17-5.18a1 1 0 0 0 0-1.69L9.54 5.98A1 1 0 0 0 8 6.82Z" />
                            </svg>
                            <svg
                              data-icon="pause"
                              viewBox="0 0 24 24"
                              fill="currentColor"
                              class="hidden size-8"
                              aria-hidden="true"
                            >
                              <path d="M7 5.75A.75.75 0 0 1 7.75 5h1.5a.75.75 0 0 1 .75.75v12.5a.75.75 0 0 1-.75.75h-1.5A.75.75 0 0 1 7 18.25V5.75Zm7 0A.75.75 0 0 1 14.75 5h1.5a.75.75 0 0 1 .75.75v12.5a.75.75 0 0 1-.75.75h-1.5a.75.75 0 0 1-.75-.75V5.75Z" />
                            </svg>
                          </button>
                        </div>
                      </div>

                      <div class="px-2 pb-2 pt-4">
                        <div class="video-preview-scrubber relative" data-role="preview-region">
                          <div
                            data-role="preview-popover"
                            class="video-preview-popover pointer-events-none absolute bottom-full left-0 z-30 mb-4 hidden -translate-x-1/2"
                          >
                            <div class="overflow-hidden rounded-2xl border border-white/10 bg-black/90 shadow-[0_22px_60px_rgba(2,6,23,0.55)]">
                              <canvas
                                data-role="preview-canvas"
                                width="320"
                                height="180"
                                class="block h-[96px] w-[172px] bg-slate-950 object-cover"
                              >
                              </canvas>
                            </div>
                            <p
                              data-role="preview-time"
                              class="mt-2 text-center text-[11px] font-semibold text-white/80"
                            >
                              {format_duration(0)}
                            </p>
                          </div>

                          <label class="sr-only" for={"video-progress-modal-#{selected.id}"}>
                            Progresso do video
                          </label>
                          <input
                            id={"video-progress-modal-#{selected.id}"}
                            data-role="progress"
                            type="range"
                            min="0"
                            max="100"
                            value="0"
                            step="0.1"
                            class="video-preview-range"
                            aria-label="Progresso do video"
                          />
                        </div>
                      </div>

                      <div class="rounded-[1.2rem] border border-white/10 bg-black/55 p-4 text-white shadow-[0_20px_40px_rgba(15,23,42,0.28)] backdrop-blur-xl">
                        <div class="flex flex-wrap items-center gap-3">
                          <button
                            type="button"
                            data-action="toggle-play"
                            class="flex size-10 items-center justify-center rounded-full bg-white/12 text-white transition hover:bg-white/18 focus:outline-none focus:ring-2 focus:ring-white/80 focus:ring-offset-2 focus:ring-offset-slate-950"
                            aria-label="Reproduzir video"
                          >
                            <svg
                              data-icon="play"
                              viewBox="0 0 24 24"
                              fill="currentColor"
                              class="ml-0.5 size-4"
                              aria-hidden="true"
                            >
                              <path d="M8 6.82v10.36c0 .79.87 1.26 1.54.84l8.17-5.18a1 1 0 0 0 0-1.69L9.54 5.98A1 1 0 0 0 8 6.82Z" />
                            </svg>
                            <svg
                              data-icon="pause"
                              viewBox="0 0 24 24"
                              fill="currentColor"
                              class="hidden size-4"
                              aria-hidden="true"
                            >
                              <path d="M7 5.75A.75.75 0 0 1 7.75 5h1.5a.75.75 0 0 1 .75.75v12.5a.75.75 0 0 1-.75.75h-1.5A.75.75 0 0 1 7 18.25V5.75Zm7 0A.75.75 0 0 1 14.75 5h1.5a.75.75 0 0 1 .75.75v12.5a.75.75 0 0 1-.75.75h-1.5a.75.75 0 0 1-.75-.75V5.75Z" />
                            </svg>
                          </button>

                          <button
                            type="button"
                            data-action="seek-backward"
                            class="flex size-10 items-center justify-center rounded-full bg-white/6 text-white/80 transition hover:bg-white/12 hover:text-white focus:outline-none focus:ring-2 focus:ring-white/80 focus:ring-offset-2 focus:ring-offset-slate-950"
                            aria-label="Voltar 5 segundos"
                          >
                            <span class="hero-backward size-4"></span>
                          </button>

                          <button
                            type="button"
                            data-action="seek-forward"
                            class="flex size-10 items-center justify-center rounded-full bg-white/6 text-white/80 transition hover:bg-white/12 hover:text-white focus:outline-none focus:ring-2 focus:ring-white/80 focus:ring-offset-2 focus:ring-offset-slate-950"
                            aria-label="Avancar 5 segundos"
                          >
                            <span class="hero-forward size-4"></span>
                          </button>

                          <button
                            type="button"
                            data-action="toggle-mute"
                            class="flex size-10 items-center justify-center rounded-full bg-white/12 text-white transition hover:bg-white/18 focus:outline-none focus:ring-2 focus:ring-white/80 focus:ring-offset-2 focus:ring-offset-slate-950"
                            aria-label="Silenciar video"
                          >
                            <svg
                              data-icon="volume-on"
                              viewBox="0 0 24 24"
                              fill="currentColor"
                              class="size-4"
                              aria-hidden="true"
                            >
                              <path d="M14.72 4.61a.75.75 0 0 1 1.06.08 10.1 10.1 0 0 1 0 14.62.75.75 0 0 1-1.14-.98 8.6 8.6 0 0 0 0-12.66.75.75 0 0 1 .08-1.06Z" />
                              <path d="M12.6 7.34a.75.75 0 0 1 1.04.18 6.08 6.08 0 0 1 0 6.96.75.75 0 1 1-1.22-.88 4.58 4.58 0 0 0 0-5.2.75.75 0 0 1 .18-1.06Z" />
                              <path d="M4 9.5A1.5 1.5 0 0 1 5.5 8H8l3.38-2.7A1 1 0 0 1 13 6.08v11.84a1 1 0 0 1-1.62.78L8 16H5.5A1.5 1.5 0 0 1 4 14.5v-5Z" />
                            </svg>
                            <svg
                              data-icon="volume-off"
                              viewBox="0 0 24 24"
                              fill="currentColor"
                              class="hidden size-4"
                              aria-hidden="true"
                            >
                              <path d="M14.5 6.08a1 1 0 0 0-1.62-.78L9.5 8H7a1.5 1.5 0 0 0-1.5 1.5v5A1.5 1.5 0 0 0 7 16h2.5l3.38 2.7a1 1 0 0 0 1.62-.78V6.08Z" />
                              <path d="M17.78 8.22a.75.75 0 0 0-1.06 1.06L18.44 11l-1.72 1.72a.75.75 0 1 0 1.06 1.06L19.5 12.06l1.72 1.72a.75.75 0 1 0 1.06-1.06L20.56 11l1.72-1.72a.75.75 0 1 0-1.06-1.06L19.5 9.94l-1.72-1.72Z" />
                            </svg>
                          </button>

                          <div class="flex min-w-[11rem] items-center gap-3 rounded-full bg-white/6 px-3 py-2 text-sm text-white/80">
                            <label class="sr-only" for={"video-volume-modal-#{selected.id}"}>
                              Volume do video
                            </label>
                            <span class="text-[11px] font-semibold uppercase tracking-[0.18em] text-white/55">
                              Volume
                            </span>
                            <input
                              id={"video-volume-modal-#{selected.id}"}
                              data-role="volume"
                              type="range"
                              min="0"
                              max="100"
                              value="100"
                              step="1"
                              class="video-volume-range"
                              aria-label="Volume do video"
                            />
                            <span
                              data-role="volume-value"
                              class="min-w-9 text-right font-semibold text-white"
                            >
                              100%
                            </span>
                          </div>

                          <div class="min-w-0 grow">
                            <p class="text-sm font-medium text-white/92">
                              <span data-role="current-time">{format_duration(0)}</span>
                              <span class="text-white/35"> / </span>
                              <span data-role="duration-inline">{format_duration(0)}</span>
                            </p>
                          </div>

                          <div class="flex items-center gap-2 rounded-full bg-white/6 px-3 py-1.5 text-sm text-white/75">
                            <span class="text-[11px] font-semibold uppercase tracking-[0.18em] text-white/55">
                              Speed
                            </span>
                            <button
                              type="button"
                              data-action="speed-down"
                              class="rounded-full px-2 py-1 transition hover:bg-white/10"
                              aria-label="Diminuir velocidade"
                            >
                              -
                            </button>
                            <span
                              data-role="speed-badge"
                              class="min-w-8 text-center font-semibold text-white"
                            >
                              1x
                            </span>
                            <button
                              type="button"
                              data-action="speed-up"
                              class="rounded-full px-2 py-1 transition hover:bg-white/10"
                              aria-label="Aumentar velocidade"
                            >
                              +
                            </button>
                          </div>

                          <button
                            type="button"
                            data-action="toggle-fullscreen"
                            class="flex size-10 items-center justify-center rounded-full bg-white/6 text-white/80 transition hover:bg-white/12 hover:text-white focus:outline-none focus:ring-2 focus:ring-white/80 focus:ring-offset-2 focus:ring-offset-slate-950"
                            aria-label="Ativar tela cheia"
                          >
                            <span class="hero-arrows-pointing-out size-4" data-icon="fullscreen-enter">
                            </span>
                            <span
                              class="hero-arrows-pointing-in hidden size-4"
                              data-icon="fullscreen-exit"
                            >
                            </span>
                          </button>
                        </div>
                      </div>
                    </div>

                    <aside class="space-y-5">
                      <section class="rounded-[1.4rem] border border-white/10 bg-white/8 p-6 backdrop-blur-sm">
                        <p class="text-sm font-semibold uppercase tracking-[0.2em] text-white/45">
                          Atalhos do teclado
                        </p>

                        <div class="mt-5 space-y-4 text-sm text-white/72">
                          <div class="flex items-center justify-between gap-4">
                            <span>Play / Pause</span>
                            <kbd class="rounded-md border border-white/10 bg-white/10 px-3 py-1 font-semibold text-white/88">
                              Espaço
                            </kbd>
                          </div>
                          <div class="flex items-center justify-between gap-4">
                            <span>Pular 5s</span>
                            <kbd class="rounded-md border border-white/10 bg-white/10 px-3 py-1 font-semibold text-white/88">
                              Setas Esquerda/Direita
                            </kbd>
                          </div>
                          <div class="flex items-center justify-between gap-4">
                            <span>Velocidade +/-</span>
                            <kbd class="rounded-md border border-white/10 bg-white/10 px-3 py-1 font-semibold text-white/88">
                              Setas Cima/Baixo
                            </kbd>
                          </div>
                          <div class="flex items-center justify-between gap-4">
                            <span>Resetar velocidade</span>
                            <kbd class="rounded-md border border-white/10 bg-white/10 px-3 py-1 font-semibold text-white/88">
                              R
                            </kbd>
                          </div>
                          <div class="flex items-center justify-between gap-4">
                            <span>Fullscreen</span>
                            <kbd class="rounded-md border border-white/10 bg-white/10 px-3 py-1 font-semibold text-white/88">
                              F
                            </kbd>
                          </div>
                        </div>
                      </section>

                      <section class="rounded-[1.4rem] border border-white/10 bg-white/8 p-6 backdrop-blur-sm">
                        <p class="text-sm font-semibold uppercase tracking-[0.2em] text-white/45">
                          Sobre o player
                        </p>
                        <p class="mt-5 text-base leading-8 text-white/62">
                          O OpenDrive Player usa aceleracao nativa do navegador para reproducao suave.
                          MP4, WebM e OGG continuam privados no app, com controles dedicados para
                          fullscreen, velocidade e navegacao rapida por teclado.
                        </p>
                      </section>
                    </aside>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
