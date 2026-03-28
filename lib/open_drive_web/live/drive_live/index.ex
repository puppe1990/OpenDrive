defmodule OpenDriveWeb.DriveLive.Index do
  use OpenDriveWeb, :live_view

  alias OpenDrive.Drive
  alias OpenDriveWeb.DriveLive.Components
  alias OpenDriveWeb.DriveLive.Entries

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
      |> assign(:editing_folder_id, nil)
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
         |> put_flash(:info, gettext("Folder created."))
         |> load_drive(socket.assigns.current_folder_id)}

      {:error, :name_conflict} ->
        {:noreply, put_flash(socket, :error, gettext("Name already used in this folder."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Unable to create folder."))}
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

  def handle_event("start_rename_folder", %{"id" => id}, socket) do
    folder_id = normalize_id(id)

    case Enum.find(socket.assigns.children.folders, &(&1.id == folder_id)) do
      nil ->
        {:noreply, socket}

      folder ->
        {:noreply,
         socket
         |> assign(:editing_folder_id, folder_id)
         |> assign(:rename_form, to_form(%{"name" => folder.name}, as: "rename"))}
    end
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
         |> put_flash(
           :info,
           ngettext(
             "%{count} item sent to the trash.",
             "%{count} items sent to the trash.",
             length(entries)
           )
         )
         |> load_drive(socket.assigns.current_folder_id)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:confirm_bulk_delete, false)
         |> put_flash(:error, gettext("Unable to delete the selected items."))}
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

  def handle_event("cancel_rename_folder", _params, socket) do
    {:noreply, clear_rename_state(socket)}
  end

  def handle_event("rename_folder", %{"folder_id" => id, "rename" => %{"name" => name}}, socket) do
    case Drive.rename_folder(socket.assigns.current_scope, normalize_id(id), %{name: name}) do
      {:ok, _folder} ->
        {:noreply,
         socket
         |> clear_rename_state()
         |> put_flash(:info, gettext("Folder renamed."))
         |> load_drive(socket.assigns.current_folder_id)}

      {:error, :name_conflict} ->
        {:noreply, put_flash(socket, :error, gettext("Name already used in this folder."))}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> clear_rename_state()
         |> put_flash(:error, gettext("Folder not found."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Unable to rename folder."))}
    end
  end

  def handle_event("rename_file", %{"file_id" => id, "rename" => %{"name" => name}}, socket) do
    case Drive.rename_file(socket.assigns.current_scope, normalize_id(id), %{name: name}) do
      {:ok, _file} ->
        {:noreply,
         socket
         |> clear_rename_state()
         |> put_flash(:info, gettext("File renamed."))
         |> load_drive(socket.assigns.current_folder_id)}

      {:error, :name_conflict} ->
        {:noreply, put_flash(socket, :error, gettext("Name already used in this folder."))}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> clear_rename_state()
         |> put_flash(:error, gettext("File not found."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Unable to rename file."))}
    end
  end

  def handle_event("open_image", %{"id" => id}, socket) do
    image_id = normalize_id(id)

    socket =
      if Enum.any?(Entries.visible_images(socket.assigns.entries), &(&1.id == image_id)) do
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
     |> put_flash(:info, gettext("Upload complete."))
     |> load_drive(socket.assigns.current_folder_id)}
  end

  def handle_event("open_video", %{"id" => id}, socket) do
    video_id = normalize_id(id)

    socket =
      if Enum.any?(Entries.visible_videos(socket.assigns.entries), &(&1.id == video_id)) do
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
      Entries.apply(children, controls)

    assign(socket,
      entries: entries,
      selected_entries:
        Entries.sanitize_selected(entries, socket.assigns[:selected_entries] || MapSet.new()),
      selected_image_id: Entries.selected_image_id(entries, socket.assigns[:selected_image_id]),
      selected_video_id: Entries.selected_video_id(entries, socket.assigns[:selected_video_id]),
      workspace_used_size: Drive.workspace_used_size(socket.assigns.current_scope),
      folder_count: length(children.folders),
      file_count: length(children.files),
      total_size: Enum.reduce(children.files, 0, &(&1.file_object.size + &2))
    )
  end

  defp clear_rename_state(socket) do
    socket
    |> assign(:editing_folder_id, nil)
    |> assign(:editing_file_id, nil)
    |> assign(:rename_form, to_form(%{"name" => ""}, as: "rename"))
  end

  defp editing_folder(entries, editing_folder_id) do
    Enum.find(entries, &(&1.kind == :folder and &1.id == editing_folder_id))
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
    Entries.selected(entries, selected_keys)
  end

  defp selected_file_entries(entries, selected_keys) do
    Entries.selected_files(entries, selected_keys)
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

  defp next_sort(current_sort, "name") when current_sort == "name_asc", do: "name_desc"
  defp next_sort(_current_sort, "name"), do: "name_asc"

  defp next_sort(current_sort, "type") when current_sort == "type_asc", do: "type_desc"
  defp next_sort(_current_sort, "type"), do: "type_asc"

  defp next_sort(current_sort, "modified") when current_sort == "modified_desc",
    do: "modified_asc"

  defp next_sort(_current_sort, "modified"), do: "modified_desc"

  defp next_sort(current_sort, "size") when current_sort == "size_desc", do: "size_asc"
  defp next_sort(_current_sort, "size"), do: "size_desc"

  defp current_view(socket), do: socket.assigns.controls["view"] || "grid"

  defp selected_image(entries, selected_image_id),
    do: Entries.selected_image(entries, selected_image_id)

  defp selected_video(entries, selected_video_id),
    do: Entries.selected_video(entries, selected_video_id)

  defp visible_entry_keys(entries), do: Entries.visible_entry_keys(entries)

  defp selected_all_entries?(entries, selected_keys),
    do: Entries.selected_all?(entries, selected_keys)

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
    images = Entries.visible_images(socket.assigns.entries)

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

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:selected_image, selected_image(assigns.entries, assigns.selected_image_id))
      |> assign(:selected_video, selected_video(assigns.entries, assigns.selected_video_id))
      |> assign(:editing_folder, editing_folder(assigns.entries, assigns.editing_folder_id))
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
      <section class="rounded-[2.25rem] border border-slate-200/80 bg-[radial-gradient(circle_at_top_left,rgba(14,165,233,0.12),transparent_24%),radial-gradient(circle_at_bottom_right,rgba(59,130,246,0.08),transparent_24%),linear-gradient(180deg,#f8fbff_0%,#f2f6fc_100%)] p-4 shadow-[0_30px_90px_rgba(148,163,184,0.16)] ring-1 ring-white/70 lg:p-6">
        <div class="grid gap-5 lg:grid-cols-[240px_minmax(0,1fr)]">
          <Components.sidebar view={assigns} />
          <Components.main_content view={assigns} />

          <%= if selected = @editing_file do %>
            <div class="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/70 p-4">
              <button
                type="button"
                phx-click="cancel_rename_file"
                class="absolute inset-0 cursor-default"
                aria-label={gettext("Close rename file modal")}
              >
              </button>

              <div class="relative z-10 w-full max-w-xl overflow-hidden rounded-[2rem] bg-white shadow-2xl ring-1 ring-slate-200">
                <div class="border-b border-slate-200 px-6 py-5">
                  <p class="text-xs font-semibold uppercase tracking-[0.24em] text-sky-600">
                    {gettext("Rename file")}
                  </p>
                  <h2 class="mt-2 text-2xl font-bold tracking-tight text-slate-950">
                    {selected.name}
                  </h2>
                  <p class="mt-2 text-sm text-slate-500">
                    {gettext(
                      "The name will be updated in Drive and the file key will be moved in S3."
                    )}
                  </p>
                </div>

                <.form for={@rename_form} phx-submit="rename_file" class="space-y-5 px-6 py-6">
                  <input type="hidden" name="file_id" value={selected.id} />

                  <div>
                    <label class="block text-sm font-medium text-slate-700">
                      {gettext("New name")}
                    </label>
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
                      {gettext("Cancel")}
                    </button>
                    <button
                      type="submit"
                      class="rounded-xl bg-slate-950 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-slate-800"
                    >
                      {gettext("Save")}
                    </button>
                  </div>
                </.form>
              </div>
            </div>
          <% end %>

          <%= if selected = @editing_folder do %>
            <div class="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/70 p-4">
              <button
                type="button"
                phx-click="cancel_rename_folder"
                class="absolute inset-0 cursor-default"
                aria-label={gettext("Close rename folder modal")}
              >
              </button>

              <div class="relative z-10 w-full max-w-xl overflow-hidden rounded-[2rem] bg-white shadow-2xl ring-1 ring-slate-200">
                <div class="border-b border-slate-200 px-6 py-5">
                  <p class="text-xs font-semibold uppercase tracking-[0.24em] text-sky-600">
                    {gettext("Rename folder")}
                  </p>
                  <h2 class="mt-2 text-2xl font-bold tracking-tight text-slate-950">
                    {selected.name}
                  </h2>
                  <p class="mt-2 text-sm text-slate-500">
                    {gettext("The new name will be displayed immediately for this workspace.")}
                  </p>
                </div>

                <.form for={@rename_form} phx-submit="rename_folder" class="space-y-5 px-6 py-6">
                  <input type="hidden" name="folder_id" value={selected.id} />

                  <div>
                    <label class="block text-sm font-medium text-slate-700">
                      {gettext("New name")}
                    </label>
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
                    {gettext("Folder · updated at this Drive level")}
                  </div>

                  <div class="flex items-center justify-end gap-3">
                    <button
                      type="button"
                      phx-click="cancel_rename_folder"
                      class="rounded-xl px-4 py-2.5 text-sm font-medium text-slate-500 transition hover:bg-slate-100"
                    >
                      {gettext("Cancel")}
                    </button>
                    <button
                      type="submit"
                      class="rounded-xl bg-slate-950 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-slate-800"
                    >
                      {gettext("Save")}
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
                aria-label={gettext("Close delete file modal")}
              >
              </button>

              <div class="relative z-10 w-full max-w-lg overflow-hidden rounded-[2rem] bg-white shadow-2xl ring-1 ring-slate-200">
                <div class="border-b border-slate-200 px-6 py-5">
                  <p class="text-xs font-semibold uppercase tracking-[0.24em] text-rose-600">
                    {gettext("Delete file")}
                  </p>
                  <h2 class="mt-2 text-2xl font-bold tracking-tight text-slate-950">
                    {gettext("Are you sure?")}
                  </h2>
                  <p class="mt-2 text-sm text-slate-500">
                    {gettext("The file %{name} will be sent to the trash.", name: selected.name)}
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
                      {gettext("Cancel")}
                    </button>
                    <button
                      type="button"
                      phx-click="confirm_delete_file"
                      phx-value-id={selected.id}
                      class="rounded-xl bg-rose-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-rose-700"
                    >
                      {gettext("Delete")}
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
                aria-label={gettext("Close delete folder modal")}
              >
              </button>

              <div class="relative z-10 w-full max-w-lg overflow-hidden rounded-[2rem] bg-white shadow-2xl ring-1 ring-slate-200">
                <div class="border-b border-slate-200 px-6 py-5">
                  <p class="text-xs font-semibold uppercase tracking-[0.24em] text-rose-600">
                    {gettext("Delete folder")}
                  </p>
                  <h2 class="mt-2 text-2xl font-bold tracking-tight text-slate-950">
                    {gettext("Are you sure?")}
                  </h2>
                  <p class="mt-2 text-sm text-slate-500">
                    {gettext("The folder %{name} will be sent to the trash.", name: selected.name)}
                  </p>
                </div>

                <div class="space-y-5 px-6 py-6">
                  <div class="rounded-2xl bg-slate-50 px-4 py-3 text-sm text-slate-500 ring-1 ring-slate-200">
                    {gettext(
                      "Items inside this folder will also stop appearing in the current Drive."
                    )}
                  </div>

                  <div class="flex items-center justify-end gap-3">
                    <button
                      type="button"
                      phx-click="cancel_delete_folder"
                      class="rounded-xl px-4 py-2.5 text-sm font-medium text-slate-500 transition hover:bg-slate-100"
                    >
                      {gettext("Cancel")}
                    </button>
                    <button
                      type="button"
                      phx-click="confirm_delete_folder"
                      phx-value-id={selected.id}
                      class="rounded-xl bg-rose-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-rose-700"
                    >
                      {gettext("Delete")}
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
                aria-label={gettext("Close bulk delete modal")}
              >
              </button>

              <div class="relative z-10 w-full max-w-lg overflow-hidden rounded-[2rem] bg-white shadow-2xl ring-1 ring-slate-200">
                <div class="border-b border-slate-200 px-6 py-5">
                  <p class="text-xs font-semibold uppercase tracking-[0.24em] text-rose-600">
                    {gettext("Bulk delete")}
                  </p>
                  <h2 class="mt-2 text-2xl font-bold tracking-tight text-slate-950">
                    {gettext("Confirm deletion")}
                  </h2>
                  <p class="mt-2 text-sm text-slate-500">
                    {gettext("%{count} selected item(s) will be sent to the trash.",
                      count: length(@selected_list_entries)
                    )}
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
                      {gettext("Cancel")}
                    </button>
                    <button
                      type="button"
                      phx-click="confirm_bulk_delete"
                      class="rounded-xl bg-rose-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-rose-700"
                    >
                      {gettext("Delete selected")}
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
                aria-label={gettext("Close preview")}
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
                    aria-label={gettext("Close")}
                  >
                    <.icon name="hero-x-mark" class="size-5" />
                  </button>
                </div>

                <div class="relative bg-[radial-gradient(circle_at_top,#1e293b_0%,#020617_65%)] p-4 sm:p-6">
                  <button
                    type="button"
                    phx-click="prev_image"
                    class="absolute left-6 top-1/2 z-20 -translate-y-1/2 rounded-full bg-slate-950/70 p-3 text-white shadow-lg ring-1 ring-white/15 transition hover:bg-slate-900"
                    aria-label={gettext("Previous photo")}
                  >
                    <.icon name="hero-chevron-left" class="size-6" />
                  </button>

                  <button
                    type="button"
                    phx-click="next_image"
                    class="absolute right-6 top-1/2 z-20 -translate-y-1/2 rounded-full bg-slate-950/70 p-3 text-white shadow-lg ring-1 ring-white/15 transition hover:bg-slate-900"
                    aria-label={gettext("Next photo")}
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
                aria-label={gettext("Close video player")}
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
                    aria-label={gettext("Close")}
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
                            {gettext("Speed")} <span data-role="speed">1x</span>
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
                          aria-label={gettext("Play video")}
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
                          {gettext("Video progress")}
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
                          aria-label={gettext("Video progress")}
                        />
                      </div>
                    </div>

                    <div class="rounded-[1.2rem] border border-white/10 bg-black/55 p-4 text-white shadow-[0_20px_40px_rgba(15,23,42,0.28)] backdrop-blur-xl">
                      <div class="flex flex-wrap items-center gap-3">
                        <button
                          type="button"
                          data-action="toggle-play"
                          class="flex size-10 items-center justify-center rounded-full bg-white/12 text-white transition hover:bg-white/18 focus:outline-none focus:ring-2 focus:ring-white/80 focus:ring-offset-2 focus:ring-offset-slate-950"
                          aria-label={gettext("Play video")}
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
                          aria-label={gettext("Go back 5 seconds")}
                        >
                          <span class="hero-backward size-4"></span>
                        </button>

                        <button
                          type="button"
                          data-action="seek-forward"
                          class="flex size-10 items-center justify-center rounded-full bg-white/6 text-white/80 transition hover:bg-white/12 hover:text-white focus:outline-none focus:ring-2 focus:ring-white/80 focus:ring-offset-2 focus:ring-offset-slate-950"
                          aria-label={gettext("Go forward 5 seconds")}
                        >
                          <span class="hero-forward size-4"></span>
                        </button>

                        <button
                          type="button"
                          data-action="toggle-mute"
                          class="flex size-10 items-center justify-center rounded-full bg-white/12 text-white transition hover:bg-white/18 focus:outline-none focus:ring-2 focus:ring-white/80 focus:ring-offset-2 focus:ring-offset-slate-950"
                          aria-label={gettext("Mute video")}
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
                            {gettext("Video volume")}
                          </label>
                          <span class="text-[11px] font-semibold uppercase tracking-[0.18em] text-white/55">
                            {gettext("Volume")}
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
                            aria-label={gettext("Video volume")}
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
                            {gettext("Speed")}
                          </span>
                          <button
                            type="button"
                            data-action="speed-down"
                            class="rounded-full px-2 py-1 transition hover:bg-white/10"
                            aria-label={gettext("Decrease speed")}
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
                            aria-label={gettext("Increase speed")}
                          >
                            +
                          </button>
                        </div>

                        <button
                          type="button"
                          data-action="toggle-fullscreen"
                          class="flex size-10 items-center justify-center rounded-full bg-white/6 text-white/80 transition hover:bg-white/12 hover:text-white focus:outline-none focus:ring-2 focus:ring-white/80 focus:ring-offset-2 focus:ring-offset-slate-950"
                          aria-label={gettext("Enable fullscreen")}
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
                        {gettext("Keyboard shortcuts")}
                      </p>

                      <div class="mt-5 space-y-4 text-sm text-white/72">
                        <div class="flex items-center justify-between gap-4">
                          <span>{gettext("Play / Pause")}</span>
                          <kbd class="rounded-md border border-white/10 bg-white/10 px-3 py-1 font-semibold text-white/88">
                            {gettext("Space")}
                          </kbd>
                        </div>
                        <div class="flex items-center justify-between gap-4">
                          <span>{gettext("Skip 5s")}</span>
                          <kbd class="rounded-md border border-white/10 bg-white/10 px-3 py-1 font-semibold text-white/88">
                            {gettext("Left/Right arrows")}
                          </kbd>
                        </div>
                        <div class="flex items-center justify-between gap-4">
                          <span>{gettext("Speed +/-")}</span>
                          <kbd class="rounded-md border border-white/10 bg-white/10 px-3 py-1 font-semibold text-white/88">
                            {gettext("Up/Down arrows")}
                          </kbd>
                        </div>
                        <div class="flex items-center justify-between gap-4">
                          <span>{gettext("Reset speed")}</span>
                          <kbd class="rounded-md border border-white/10 bg-white/10 px-3 py-1 font-semibold text-white/88">
                            R
                          </kbd>
                        </div>
                        <div class="flex items-center justify-between gap-4">
                          <span>{gettext("Fullscreen")}</span>
                          <kbd class="rounded-md border border-white/10 bg-white/10 px-3 py-1 font-semibold text-white/88">
                            F
                          </kbd>
                        </div>
                      </div>
                    </section>

                    <section class="rounded-[1.4rem] border border-white/10 bg-white/8 p-6 backdrop-blur-sm">
                      <p class="text-sm font-semibold uppercase tracking-[0.2em] text-white/45">
                        {gettext("About the player")}
                      </p>
                      <p class="mt-5 text-base leading-8 text-white/62">
                        {gettext(
                          "OpenDrive Player uses native browser acceleration for smooth playback. MP4, WebM, and OGG remain private in the app, with dedicated controls for fullscreen, speed, and quick keyboard navigation."
                        )}
                      </p>
                    </section>
                  </aside>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
