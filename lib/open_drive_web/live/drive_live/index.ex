defmodule OpenDriveWeb.DriveLive.Index do
  use OpenDriveWeb, :live_view

  alias OpenDrive.Drive

  @max_upload_entries 1_000
  @max_upload_file_size 250_000_000

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
      |> allow_upload(:files,
        accept: :any,
        max_entries: @max_upload_entries,
        max_file_size: @max_upload_file_size,
        auto_upload: true,
        progress: &handle_progress/3
      )
      |> assign(:folder_form, to_form(%{"name" => ""}, as: "folder"))
      |> assign(:controls, @default_controls)
      |> assign(:controls_form, to_form(@default_controls, as: "controls"))
      |> assign(:new_menu_open, true)
      |> assign(:children, %{folders: [], files: []})
      |> assign(:entries, [])
      |> assign(:selected_image_id, nil)
      |> assign(:selected_video_id, nil)
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

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :files, ref)}
  end

  def handle_event("delete_folder", %{"id" => id}, socket) do
    {:ok, _} = Drive.soft_delete_node(socket.assigns.current_scope, {:folder, id})
    {:noreply, load_drive(socket, socket.assigns.current_folder_id)}
  end

  def handle_event("delete_file", %{"id" => id}, socket) do
    {:ok, _} = Drive.soft_delete_node(socket.assigns.current_scope, {:file, id})
    {:noreply, load_drive(socket, socket.assigns.current_folder_id)}
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

  defp handle_progress(:files, entry, socket) do
    if entry.done? do
      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          upload = %{
            path: path,
            client_name: entry.client_name,
            content_type: entry.client_type,
            size: entry.client_size
          }

          Drive.upload_file(
            socket.assigns.current_scope,
            %{folder_id: socket.assigns.current_folder_id},
            upload
          )
        end)

      case result do
        %Drive.File{} ->
          {:noreply,
           socket
           |> put_flash(:info, "Upload complete.")
           |> load_drive(socket.assigns.current_folder_id)}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Upload failed for this file.")}
      end
    else
      {:noreply, socket}
    end
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
      selected_image_id: selected_image_id(entries, socket.assigns[:selected_image_id]),
      selected_video_id: selected_video_id(entries, socket.assigns[:selected_video_id]),
      folder_count: length(children.folders),
      file_count: length(children.files),
      total_size: Enum.reduce(children.files, 0, &(&1.file_object.size + &2))
    )
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
        if sort in ["modified_desc", "name_asc", "size_desc"], do: sort, else: "modified_desc"
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

  defp sort_entries(entries, "size_desc"),
    do: Enum.sort_by(entries, &{entry_order(&1), -(&1.size || -1), String.downcase(&1.name)})

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

  defp current_view(socket), do: socket.assigns.controls["view"] || "grid"

  defp translate_upload_error(:too_large),
    do: "Arquivo excede o limite de 250 MB."

  defp translate_upload_error(:not_accepted),
    do: "Tipo de arquivo nao aceito."

  defp translate_upload_error(:too_many_files),
    do: "Voce selecionou arquivos demais de uma vez."

  defp translate_upload_error(error),
    do: "Falha ao preparar o upload (#{inspect(error)})."

  defp upload_status(entry, errors) do
    cond do
      errors != [] -> :error
      entry.progress >= 100 -> :complete
      entry.progress > 0 -> :uploading
      true -> :queued
    end
  end

  defp upload_status_label(:error), do: "Falhou"
  defp upload_status_label(:complete), do: "Concluido"
  defp upload_status_label(:uploading), do: "Enviando"
  defp upload_status_label(:queued), do: "Na fila"

  defp upload_status_classes(:error), do: "bg-rose-100 text-rose-700 ring-1 ring-rose-200"

  defp upload_status_classes(:complete),
    do: "bg-emerald-100 text-emerald-700 ring-1 ring-emerald-200"

  defp upload_status_classes(:uploading), do: "bg-sky-100 text-sky-700 ring-1 ring-sky-200"
  defp upload_status_classes(:queued), do: "bg-slate-100 text-slate-600 ring-1 ring-slate-200"

  defp upload_progress_classes(:error), do: "bg-rose-400"
  defp upload_progress_classes(:complete), do: "bg-emerald-400"
  defp upload_progress_classes(:uploading), do: "bg-sky-500"
  defp upload_progress_classes(:queued), do: "bg-slate-300"

  defp upload_queue_stats(entries, uploads) do
    Enum.reduce(entries, %{queued: 0, uploading: 0, complete: 0, error: 0}, fn entry, acc ->
      status = upload_status(entry, upload_errors(uploads, entry))
      Map.update!(acc, status, &(&1 + 1))
    end)
  end

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
      |> assign(
        :upload_stats,
        upload_queue_stats(assigns.uploads.files.entries, assigns.uploads.files)
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
                <div class="h-full w-2/5 rounded-full bg-sky-400"></div>
              </div>
              <p class="mt-2 text-xs text-slate-400">
                {length(@entries)} itens visiveis · {@folder_count} pastas · {@file_count} arquivos
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
              phx-drop-target={@uploads.files.ref}
              class="rounded-[1.75rem] bg-white/90 p-4 shadow-sm ring-1 ring-slate-200/70 transition phx-drop-target-active:bg-sky-50/80 phx-drop-target-active:ring-2 phx-drop-target-active:ring-sky-400"
            >
              <form id="upload_form" phx-change="validate_upload" class="hidden">
                <.live_file_input
                  upload={@uploads.files}
                  id="folder-upload-input"
                  class="hidden"
                />
              </form>

              <div
                id="folder-upload-trigger"
                phx-hook="FilePickerTrigger"
                data-file-input="#folder-upload-input"
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
                :if={@uploads.files.entries != []}
                class="mb-4 overflow-hidden rounded-[1.5rem] bg-white shadow-sm ring-1 ring-slate-200"
              >
                <div class="flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 bg-slate-50/80 px-4 py-3">
                  <div>
                    <p class="text-sm font-semibold text-slate-900">Fila de uploads</p>
                    <p class="text-xs text-slate-500">
                      Acompanhe o progresso de cada arquivo em tempo real
                    </p>
                  </div>
                  <div class="flex flex-wrap items-center gap-2 text-[11px] font-medium">
                    <span class="rounded-full bg-slate-100 px-3 py-1 text-slate-600 ring-1 ring-slate-200">
                      {@upload_stats.queued} na fila
                    </span>
                    <span class="rounded-full bg-sky-100 px-3 py-1 text-sky-700 ring-1 ring-sky-200">
                      {@upload_stats.uploading} enviando
                    </span>
                    <span class="rounded-full bg-emerald-100 px-3 py-1 text-emerald-700 ring-1 ring-emerald-200">
                      {@upload_stats.complete} concluidos
                    </span>
                    <span class="rounded-full bg-rose-100 px-3 py-1 text-rose-700 ring-1 ring-rose-200">
                      {@upload_stats.error} com erro
                    </span>
                  </div>
                </div>

                <div
                  :for={entry <- @uploads.files.entries}
                  class="border-t border-slate-100 px-4 py-3 first:border-t-0"
                >
                  <% errors = upload_errors(@uploads.files, entry) %>
                  <% status = upload_status(entry, errors) %>
                  <div class="flex items-start justify-between gap-3">
                    <div class="min-w-0 flex-1">
                      <div class="flex flex-wrap items-center gap-2">
                        <span class="block truncate text-sm font-medium text-slate-800">
                          {entry.client_name}
                        </span>
                        <span class={[
                          "rounded-full px-2.5 py-1 text-[11px] font-semibold",
                          upload_status_classes(status)
                        ]}>
                          {upload_status_label(status)}
                        </span>
                      </div>

                      <div class="mt-2 flex items-center gap-2 text-[11px] text-slate-500">
                        <span>{format_bytes(entry.client_size)}</span>
                        <span class="text-slate-300">•</span>
                        <span>{entry.progress}% enviado</span>
                      </div>

                      <div class="mt-3 h-2 overflow-hidden rounded-full bg-slate-100">
                        <div
                          class={[
                            "h-full rounded-full transition-all duration-300",
                            upload_progress_classes(status)
                          ]}
                          style={"width: #{entry.progress}%"}
                        >
                        </div>
                      </div>

                      <div :if={errors != []} class="mt-2 space-y-1">
                        <p
                          :for={error <- errors}
                          class="text-[11px] font-medium text-rose-600"
                        >
                          {translate_upload_error(error)}
                        </p>
                      </div>
                    </div>

                    <div class="flex shrink-0 items-center gap-3">
                      <button
                        type="button"
                        phx-click="cancel_upload"
                        phx-value-ref={entry.ref}
                        class="rounded-full p-2 text-slate-400 transition hover:bg-slate-100 hover:text-slate-700"
                        aria-label={"Remover #{entry.client_name}"}
                      >
                        <.icon name="hero-x-mark" class="size-4" />
                      </button>
                    </div>
                  </div>
                </div>
              </div>

              <div
                :if={upload_errors(@uploads.files) != []}
                class="mb-4 rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3 text-xs text-amber-800"
              >
                <p :for={error <- upload_errors(@uploads.files)}>
                  {translate_upload_error(error)}
                </p>
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
                    {"Nome", "name_asc"},
                    {"Maior tamanho", "size_desc"}
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
              class="overflow-hidden rounded-[1.75rem] bg-white shadow-sm ring-1 ring-slate-200/70"
            >
              <div class="grid grid-cols-[minmax(0,1fr)_120px_120px_110px] gap-4 border-b border-slate-200 px-5 py-3 text-xs font-semibold uppercase tracking-[0.2em] text-slate-400">
                <span>Nome</span>
                <span>Tipo</span>
                <span>Modificado</span>
                <span></span>
              </div>

              <%= for entry <- @entries do %>
                <div class="grid grid-cols-[minmax(0,1fr)_120px_120px_110px] items-center gap-4 border-b border-slate-100 px-5 py-3 last:border-b-0">
                  <div class="flex min-w-0 items-center gap-3">
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

                    <div class="min-w-0">
                      <.link
                        :if={entry.kind == :folder}
                        navigate={entry.href}
                        class="block truncate font-medium text-slate-950 hover:text-sky-700"
                      >
                        {entry.name}
                      </.link>
                      <.link
                        :if={entry.kind == :file and entry.preview not in [:image, :video]}
                        href={entry.href}
                        class="block truncate font-medium text-slate-950 hover:text-sky-700"
                      >
                        {entry.name}
                      </.link>
                      <button
                        :if={entry.preview == :image}
                        type="button"
                        phx-click="open_image"
                        phx-value-id={entry.id}
                        class="block truncate font-medium text-left text-slate-950 hover:text-sky-700"
                      >
                        {entry.name}
                      </button>
                      <button
                        :if={entry.preview == :video}
                        type="button"
                        phx-click="open_video"
                        phx-value-id={entry.id}
                        class="block truncate font-medium text-left text-slate-950 hover:text-sky-700"
                      >
                        {entry.name}
                      </button>
                    </div>
                  </div>
                  <span class="text-sm text-slate-500">{entry.content_type}</span>
                  <span class="text-sm text-slate-500">{relative_time(entry.updated_at)}</span>
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
