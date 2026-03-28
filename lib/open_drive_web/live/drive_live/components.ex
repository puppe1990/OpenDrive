defmodule OpenDriveWeb.DriveLive.Components do
  @moduledoc false

  use OpenDriveWeb, :html

  alias OpenDrive.Drive

  attr :view, :map, required: true

  def sidebar(assigns) do
    ~H"""
    <aside class="space-y-5 lg:sticky lg:top-6">
      <div class="overflow-hidden rounded-[1.9rem] border border-slate-200/70 bg-[linear-gradient(180deg,rgba(255,255,255,0.98),rgba(247,250,252,0.98))] p-4 shadow-[0_24px_70px_rgba(148,163,184,0.14)] ring-1 ring-white/70 backdrop-blur">
        <div class="mb-5 border-b border-slate-200/80 pb-4">
          <div class="flex items-start gap-3">
            <div class="flex size-11 items-center justify-center rounded-[1.2rem] bg-slate-950 text-sm font-black text-white shadow-[0_12px_28px_rgba(15,23,42,0.22)]">
              OD
            </div>
            <div class="min-w-0">
              <p class="text-[11px] font-semibold uppercase tracking-[0.32em] text-slate-400">
                {gettext("Workspace")}
              </p>
              <p class="mt-2 truncate text-lg font-black tracking-tight text-slate-950">
                {@view.current_scope.tenant.name}
              </p>
              <p class="mt-1 truncate text-sm text-slate-500">{@view.current_scope.user.email}</p>
            </div>
          </div>
        </div>

        <button
          phx-click="toggle_new_menu"
          class="flex w-full items-center justify-between rounded-[1.35rem] bg-slate-950 px-4 py-3 text-left text-sm font-semibold text-white shadow-[0_16px_34px_rgba(15,23,42,0.18)] transition hover:bg-slate-800"
        >
          <span class="flex items-center gap-3">
            <span class="flex size-8 items-center justify-center rounded-xl bg-white/10">
              <.icon name="hero-plus" class="size-4" />
            </span>
            {gettext("New")}
          </span>
          <.icon
            name={if @view.new_menu_open, do: "hero-chevron-up", else: "hero-chevron-down"}
            class="size-4"
          />
        </button>

        <div
          :if={@view.new_menu_open}
          class="mt-3 space-y-4 rounded-[1.35rem] border border-slate-200/80 bg-slate-50/90 p-3"
        >
          <.form for={@view.folder_form} phx-submit="create_folder" class="space-y-2">
            <.input
              field={@view.folder_form[:name]}
              type="text"
              label={gettext("New folder")}
              required
            />
            <.button class="btn btn-primary w-full">{gettext("Create folder")}</.button>
          </.form>
        </div>

        <div class="mt-5">
          <p class="px-2 text-[11px] font-semibold uppercase tracking-[0.28em] text-slate-400">
            {gettext("Browse")}
          </p>
          <nav class="mt-3 space-y-1">
            <button
              phx-click="set_sidebar_preset"
              phx-value-preset="my_drive"
              class="flex w-full items-center gap-3 rounded-[1.2rem] px-2.5 py-2.5 text-sm font-medium text-slate-800 transition hover:bg-slate-100"
            >
              <span class="flex size-9 items-center justify-center rounded-[1rem] bg-slate-950 text-white">
                <.icon name="hero-home" class="size-4.5" />
              </span>
              {gettext("My Drive")}
            </button>
            <button
              phx-click="set_sidebar_preset"
              phx-value-preset="recent"
              class="flex w-full items-center gap-3 rounded-[1.2rem] px-2.5 py-2.5 text-sm text-slate-600 transition hover:bg-slate-100 hover:text-slate-900"
            >
              <span class="flex size-9 items-center justify-center rounded-[1rem] bg-slate-100 text-slate-600">
                <.icon name="hero-clock" class="size-4.5" />
              </span>
              {gettext("Recent")}
            </button>
            <button
              phx-click="set_sidebar_preset"
              phx-value-preset="images"
              class="flex w-full items-center gap-3 rounded-[1.2rem] px-2.5 py-2.5 text-sm text-slate-600 transition hover:bg-slate-100 hover:text-slate-900"
            >
              <span class="flex size-9 items-center justify-center rounded-[1rem] bg-sky-50 text-sky-700">
                <.icon name="hero-photo" class="size-4.5" />
              </span>
              {gettext("Images")}
            </button>
            <button
              phx-click="set_sidebar_preset"
              phx-value-preset="videos"
              class="flex w-full items-center gap-3 rounded-[1.2rem] px-2.5 py-2.5 text-sm text-slate-600 transition hover:bg-slate-100 hover:text-slate-900"
            >
              <span class="flex size-9 items-center justify-center rounded-[1rem] bg-violet-50 text-violet-700">
                <.icon name="hero-film" class="size-4.5" />
              </span>
              {gettext("Videos")}
            </button>
            <button
              phx-click="set_sidebar_preset"
              phx-value-preset="folders"
              class="flex w-full items-center gap-3 rounded-[1.2rem] px-2.5 py-2.5 text-sm text-slate-600 transition hover:bg-slate-100 hover:text-slate-900"
            >
              <span class="flex size-9 items-center justify-center rounded-[1rem] bg-amber-50 text-amber-700">
                <.icon name="hero-folder" class="size-4.5" />
              </span>
              {gettext("Folders")}
            </button>
            <.link
              navigate={~p"/app/trash"}
              class="flex items-center gap-3 rounded-[1.2rem] px-2.5 py-2.5 text-sm text-slate-600 transition hover:bg-slate-100 hover:text-slate-900"
            >
              <span class="flex size-9 items-center justify-center rounded-[1rem] bg-rose-50 text-rose-700">
                <.icon name="hero-trash" class="size-4.5" />
              </span>
              {gettext("Trash")}
            </.link>
          </nav>
        </div>

        <div class="mt-5 border-t border-slate-200/80 pt-4">
          <div class="flex items-center justify-between gap-3 rounded-[1.2rem] bg-slate-50 px-3 py-3">
            <div>
              <p class="text-[11px] font-semibold uppercase tracking-[0.26em] text-slate-400">
                {gettext("Storage")}
              </p>
              <p class="mt-1 text-base font-semibold text-slate-950">
                {format_bytes(@view.workspace_used_size)}
              </p>
            </div>
            <p class="text-sm font-medium text-slate-500">
              {@view.folder_count + @view.file_count} {gettext("items")}
            </p>
          </div>
          <div class="mt-3 h-1.5 overflow-hidden rounded-full bg-slate-200">
            <div class="h-full w-2/3 rounded-full bg-slate-950"></div>
          </div>
          <p class="mt-2 px-1 text-xs text-slate-400">
            {gettext("Workspace overview")}
          </p>
        </div>
      </div>
    </aside>
    """
  end

  attr :view, :map, required: true

  def main_content(assigns) do
    ~H"""
    <div class="space-y-5">
      <section
        id="folder-dropzone"
        phx-hook="DirectUploadZone"
        data-initiate-url={~p"/app/uploads"}
        data-proxy-url={~p"/app/uploads/proxy"}
        data-complete-url={~p"/app/uploads/complete"}
        data-folder-id={@view.current_folder_id || ""}
        data-max-file-size={Drive.max_upload_file_size()}
        data-backend-fallback-size={Drive.backend_upload_fallback_size()}
        class="rounded-[2rem] border border-slate-200/70 bg-[linear-gradient(180deg,rgba(255,255,255,0.96),rgba(247,250,255,0.98))] p-4 shadow-[0_20px_60px_rgba(148,163,184,0.14)] ring-1 ring-white/70 transition phx-drop-target-active:bg-sky-50/80 phx-drop-target-active:ring-2 phx-drop-target-active:ring-sky-400"
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
          aria-label={gettext("Select files from device")}
          class="mb-4 block cursor-pointer overflow-hidden rounded-[1.65rem] border border-dashed border-slate-200 bg-[radial-gradient(circle_at_top,rgba(125,211,252,0.18),transparent_35%),linear-gradient(180deg,rgba(248,250,252,0.98),rgba(239,246,255,0.94))] px-4 py-6 text-center transition hover:border-sky-300 hover:bg-sky-50/70 focus:outline-none focus:ring-2 focus:ring-sky-400 focus:ring-offset-2"
        >
          <div class="flex flex-col items-center justify-center gap-3 sm:flex-row sm:text-left">
            <div class="flex size-12 items-center justify-center rounded-2xl bg-white text-sky-600 shadow-sm ring-1 ring-sky-100">
              <.icon name="hero-arrow-up-tray" class="size-6" />
            </div>
            <div>
              <p class="text-sm font-semibold text-slate-900">
                {gettext("Drag files into this folder")}
              </p>
              <p class="mt-1 text-xs text-slate-500">
                {gettext("Upload starts as soon as you drop the file")}
              </p>
              <p class="mt-1 text-xs text-slate-400">
                {gettext("You can drop multiple files at once")}
              </p>
              <p class="mt-2 text-[11px] uppercase tracking-[0.18em] text-slate-400">
                {gettext("Click to choose files from your device")}
              </p>
            </div>
          </div>
        </div>

        <div
          id="direct-upload-queue"
          data-direct-upload-queue
          phx-update="ignore"
          class="mb-4 overflow-hidden rounded-[1.65rem] bg-white shadow-sm ring-1 ring-slate-200"
          hidden
        >
          <div class="flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 bg-slate-50/80 px-4 py-3">
            <div>
              <p class="text-sm font-semibold text-slate-900">{gettext("Upload queue")}</p>
              <p class="text-xs text-slate-500">
                {gettext("Follow the progress of each file in real time")}
              </p>
            </div>
            <div class="flex flex-wrap items-center gap-2 text-[11px] font-medium">
              <span
                data-upload-stat="queued"
                class="rounded-full bg-slate-100 px-3 py-1 text-slate-600 ring-1 ring-slate-200"
              >
                {gettext("0 queued")}
              </span>
              <span
                data-upload-stat="uploading"
                class="rounded-full bg-sky-100 px-3 py-1 text-sky-700 ring-1 ring-sky-200"
              >
                {gettext("0 uploading")}
              </span>
              <span
                data-upload-stat="complete"
                class="rounded-full bg-emerald-100 px-3 py-1 text-emerald-700 ring-1 ring-emerald-200"
              >
                {gettext("0 completed")}
              </span>
              <span
                data-upload-stat="error"
                class="rounded-full bg-rose-100 px-3 py-1 text-rose-700 ring-1 ring-rose-200"
              >
                {gettext("0 with error")}
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
          for={@view.controls_form}
          id="controls_form"
          phx-change="update_controls"
          class="flex flex-wrap items-center gap-3 rounded-[1.6rem] border border-slate-200/80 bg-white/80 p-3 shadow-[inset_0_1px_0_rgba(255,255,255,0.9)]"
        >
          <label class="flex min-w-[220px] flex-1 items-center gap-3 rounded-2xl border border-slate-200/80 bg-slate-50 px-4 py-3 shadow-[inset_0_1px_0_rgba(255,255,255,0.9)]">
            <.icon name="hero-magnifying-glass" class="size-5 text-slate-400" />
            <input
              type="text"
              name={@view.controls_form[:query].name}
              value={@view.controls_form[:query].value}
              placeholder={gettext("Search by name")}
              class="w-full bg-transparent text-sm outline-none placeholder:text-slate-400"
            />
          </label>

          <.input
            field={@view.controls_form[:type]}
            type="select"
            options={[
              {gettext("All"), "all"},
              {gettext("Folders"), "folders"},
              {gettext("Files"), "files"},
              {gettext("Images"), "images"},
              {gettext("Videos"), "videos"}
            ]}
            class="select rounded-2xl bg-slate-100 px-4"
          />

          <.input
            field={@view.controls_form[:sort]}
            type="select"
            options={[
              {gettext("Recently modified"), "modified_desc"},
              {gettext("Oldest modified"), "modified_asc"},
              {gettext("Name"), "name_asc"},
              {gettext("Name Z-A"), "name_desc"},
              {gettext("Type"), "type_asc"},
              {gettext("Type Z-A"), "type_desc"},
              {gettext("Largest size"), "size_desc"},
              {gettext("Smallest size"), "size_asc"}
            ]}
            class="select rounded-2xl bg-slate-100 px-4"
          />

          <input
            type="hidden"
            name={@view.controls_form[:view].name}
            value={@view.controls_form[:view].value}
          />
        </.form>

        <div class="mt-4 flex items-center justify-between gap-3 border-t border-slate-200 pt-4">
          <div class="flex items-center gap-2 text-sm text-slate-500">
            <span class="rounded-full border border-slate-200 bg-white px-3 py-1.5 shadow-sm">
              {gettext("%{count} results", count: length(@view.entries))}
            </span>
            <span
              :if={@view.controls["type"] != "all"}
              class="rounded-full border border-sky-200 bg-sky-50 px-3 py-1.5 text-sky-700"
            >
              {gettext("filter: %{value}", value: @view.controls["type"])}
            </span>
          </div>

          <div class="inline-flex rounded-2xl border border-slate-200 bg-white p-1 shadow-sm">
            <button
              phx-click="set_view"
              phx-value-view="grid"
              class={[
                "rounded-xl px-3 py-2 text-sm transition",
                @view.controls["view"] == "grid" && "bg-white shadow-sm text-slate-950",
                @view.controls["view"] != "grid" && "text-slate-500"
              ]}
            >
              <.icon name="hero-squares-2x2" class="size-5" />
            </button>
            <button
              phx-click="set_view"
              phx-value-view="list"
              class={[
                "rounded-xl px-3 py-2 text-sm transition",
                @view.controls["view"] == "list" && "bg-white shadow-sm text-slate-950",
                @view.controls["view"] != "list" && "text-slate-500"
              ]}
            >
              <.icon name="hero-list-bullet" class="size-5" />
            </button>
          </div>
        </div>
      </section>

      <.empty_state :if={@view.entries == []} />
      <.grid_entries :if={@view.entries != [] and @view.controls["view"] == "grid"} view={@view} />
      <.list_entries :if={@view.entries != [] and @view.controls["view"] == "list"} view={@view} />
    </div>
    """
  end

  attr :view, :map, required: true

  def grid_entries(assigns) do
    ~H"""
    <section class="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
      <%= for entry <- @view.entries do %>
        <article class="overflow-hidden rounded-[1.7rem] border border-slate-200/80 bg-[linear-gradient(180deg,rgba(255,255,255,0.98),rgba(248,250,252,0.98))] shadow-[0_18px_55px_rgba(148,163,184,0.14)] ring-1 ring-white/80 transition duration-200 hover:-translate-y-0.5 hover:shadow-[0_26px_70px_rgba(148,163,184,0.22)]">
          <div class="flex items-center gap-3 border-b border-slate-100 px-4 py-4">
            <div class="flex min-w-0 flex-1 items-center gap-3">
              <div class={[
                "flex size-10 items-center justify-center rounded-2xl",
                entry.kind == :folder && "bg-sky-100 text-sky-700",
                entry.kind == :file && "bg-slate-100 text-slate-700"
              ]}>
                <.icon name={preview_icon(entry.preview)} class="size-5" />
              </div>
              <div class="min-w-0">
                <p class="truncate text-sm font-semibold text-slate-950">{entry.name}</p>
                <p class="text-xs text-slate-400">{relative_time(entry.updated_at)}</p>
              </div>
            </div>
            <div class="flex shrink-0 items-center gap-1">
              <button
                :if={entry.kind == :folder}
                phx-click="start_rename_folder"
                phx-value-id={entry.id}
                class="rounded-lg p-2 text-slate-400 transition hover:bg-slate-100 hover:text-sky-600"
              >
                <.icon name="hero-pencil-square" class="size-4" />
              </button>
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
          </div>

          <div class="bg-[radial-gradient(circle_at_top,rgba(125,211,252,0.12),transparent_36%),linear-gradient(180deg,#f8fafc_0%,#eef3f8_100%)] p-4">
            <.link
              :if={entry.kind == :folder}
              navigate={entry.href}
              class="flex h-36 items-center justify-center rounded-[1.25rem] border border-dashed border-slate-300 text-slate-500"
            >
              <div class="text-center">
                <.icon name="hero-folder" class="mx-auto size-10 text-sky-600" />
                <p class="mt-2 text-sm font-medium">{gettext("Open folder")}</p>
              </div>
            </.link>

            <button
              :if={entry.preview == :image}
              type="button"
              phx-click="open_image"
              phx-value-id={entry.id}
              class="block w-full overflow-hidden rounded-[1.25rem] ring-1 ring-slate-200 transition hover:ring-sky-300"
            >
              <img src={entry.href} alt={entry.name} class="h-36 w-full object-cover" />
            </button>

            <button
              :if={entry.preview == :video}
              type="button"
              phx-click="open_video"
              phx-value-id={entry.id}
              class="video-preview-shell group relative block h-36 w-full overflow-hidden rounded-[1.25rem] text-left ring-1 ring-slate-200 transition hover:ring-sky-300 focus:outline-none focus:ring-2 focus:ring-sky-400 focus:ring-offset-2"
              aria-label={gettext("Open video %{name}", name: entry.name)}
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
                  {gettext("Video")}
                </span>
                <span class="rounded-full border border-white/15 bg-white/12 px-2.5 py-1 text-[11px] font-medium text-white/85 shadow-sm backdrop-blur-md">
                  {gettext("Open player")}
                </span>
              </div>

              <div class="absolute inset-0 flex items-center justify-center">
                <div class="video-preview-play flex size-14 items-center justify-center rounded-full border border-white/20 bg-white/18 text-white shadow-[0_18px_45px_rgba(15,23,42,0.35)] backdrop-blur-xl transition duration-300 group-hover:scale-105 group-hover:bg-white/24">
                  <svg viewBox="0 0 24 24" fill="currentColor" class="ml-1 size-6" aria-hidden="true">
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
                <p class="mt-2 text-sm">{entry.content_type || gettext("File")}</p>
              </div>
            </div>
          </div>

          <div class="flex items-center justify-between px-4 py-4 text-sm">
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
              {gettext("Download")}
            </.link>
          </div>
        </article>
      <% end %>
    </section>
    """
  end

  attr :view, :map, required: true

  def list_entries(assigns) do
    ~H"""
    <section
      id="drive-list-view"
      phx-hook="ResizableListColumns"
      data-storage-key={"drive-list-columns-#{@view.current_scope.tenant.id}"}
      class="overflow-hidden rounded-[2rem] border border-slate-200/80 bg-[linear-gradient(180deg,rgba(255,255,255,0.98),rgba(248,250,252,0.98))] shadow-[0_24px_70px_rgba(148,163,184,0.14)] ring-1 ring-white/70"
    >
      <div class="flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 bg-[linear-gradient(180deg,rgba(248,250,252,0.96),rgba(241,245,249,0.88))] px-5 py-4">
        <div class="flex flex-wrap items-center gap-3 text-sm text-slate-500">
          <label class="flex items-center gap-2 rounded-full bg-white px-3 py-2 ring-1 ring-slate-200">
            <input
              type="checkbox"
              phx-click="toggle_all_entries"
              phx-value-state={if @view.all_list_entries_selected, do: "unchecked", else: "checked"}
              checked={@view.all_list_entries_selected}
              class="checkbox checkbox-sm rounded-md border-slate-300"
            />
            <span>{gettext("Select all")}</span>
          </label>
          <span class="rounded-full bg-white px-3 py-2 ring-1 ring-slate-200">
            {gettext("Selected: %{count}", count: length(@view.selected_list_entries))}
          </span>
          <span
            :if={@view.selected_file_entries != []}
            class="rounded-full bg-sky-50 px-3 py-2 text-sky-700 ring-1 ring-sky-200"
          >
            {gettext("%{count} file(s) for ZIP", count: length(@view.selected_file_entries))}
          </span>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <form method="post" action={~p"/app/files/download-zip"}>
            <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
            <%= for entry <- @view.selected_file_entries do %>
              <input type="hidden" name="file_ids[]" value={entry.id} />
            <% end %>
            <button
              type="submit"
              disabled={@view.selected_file_entries == []}
              class="rounded-xl bg-sky-600 px-4 py-2.5 text-sm font-semibold text-white transition enabled:hover:bg-sky-700 disabled:cursor-not-allowed disabled:bg-slate-200 disabled:text-slate-400"
            >
              {gettext("Download ZIP")}
            </button>
          </form>

          <button
            type="button"
            phx-click="open_bulk_delete_modal"
            disabled={@view.selected_list_entries == []}
            class="rounded-xl bg-rose-600 px-4 py-2.5 text-sm font-semibold text-white transition enabled:hover:bg-rose-700 disabled:cursor-not-allowed disabled:bg-slate-200 disabled:text-slate-400"
          >
            {gettext("Delete selected")}
          </button>
        </div>
      </div>

      <div class="drive-list-grid gap-4 border-b border-slate-200 px-5 py-3 text-xs font-semibold uppercase tracking-[0.2em] text-slate-400">
        <span class="flex items-center justify-center">{gettext("Sel.")}</span>
        <.list_header_column view={@view} field="name" label={gettext("Name")} min="260" max="820" />
        <.list_header_column view={@view} field="type" label={gettext("Type")} min="120" max="320" />
        <.list_header_column
          view={@view}
          field="modified"
          label={gettext("Modified")}
          min="110"
          max="280"
        />
        <.list_header_column view={@view} field="size" label={gettext("Size")} min="110" max="280" />
        <span></span>
      </div>

      <%= for entry <- @view.entries do %>
        <div class="drive-list-grid items-center gap-4 border-b border-slate-100 px-5 py-3 transition hover:bg-slate-50/70 last:border-b-0">
          <label class="flex items-center justify-center">
            <input
              type="checkbox"
              phx-click="toggle_entry_selection"
              phx-value-key={entry_selection_key(entry)}
              checked={MapSet.member?(@view.selected_entries, entry_selection_key(entry))}
              class="checkbox checkbox-sm rounded-md border-slate-300"
            />
          </label>
          <div class="flex min-w-0 overflow-hidden items-center gap-3">
            <div class={[
              "flex size-10 shrink-0 items-center justify-center rounded-2xl",
              entry.kind == :folder && "bg-sky-100 text-sky-700",
              entry.kind == :file && "bg-slate-100 text-slate-700"
            ]}>
              <.icon name={preview_icon(entry.preview)} class="size-5" />
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
          <span class="min-w-0 truncate text-sm text-slate-500">{format_bytes(entry.size)}</span>
          <div class="flex items-center justify-end gap-2">
            <.link
              :if={entry.kind == :file}
              href={entry.href}
              class="rounded-xl bg-slate-100 px-3 py-2 text-sm text-slate-700 hover:bg-slate-200"
            >
              {gettext("Download")}
            </.link>
            <button
              :if={entry.kind == :folder}
              phx-click="start_rename_folder"
              phx-value-id={entry.id}
              class="rounded-lg p-2 text-slate-400 hover:bg-slate-100 hover:text-sky-600"
            >
              <.icon name="hero-pencil-square" class="size-4" />
            </button>
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
    """
  end

  def empty_state(assigns) do
    ~H"""
    <section class="overflow-hidden rounded-[2rem] border border-dashed border-slate-300 bg-[radial-gradient(circle_at_top,rgba(125,211,252,0.18),transparent_30%),linear-gradient(180deg,rgba(255,255,255,0.96),rgba(248,250,252,0.98))] px-8 py-16 text-center shadow-[0_20px_60px_rgba(148,163,184,0.12)]">
      <div class="mx-auto flex size-18 items-center justify-center rounded-[1.6rem] bg-white shadow-sm ring-1 ring-slate-200">
        <.icon name="hero-folder-open" class="size-8 text-sky-500" />
      </div>
      <h2 class="mt-5 text-2xl font-semibold text-slate-950">{gettext("Nothing here yet")}</h2>
      <p class="mx-auto mt-2 max-w-xl text-sm leading-6 text-slate-500">
        {gettext("Create a folder, upload a file, or adjust the filters to find what you need.")}
      </p>
    </section>
    """
  end

  attr :view, :map, required: true
  attr :field, :string, required: true
  attr :label, :string, required: true
  attr :min, :string, required: true
  attr :max, :string, required: true

  defp list_header_column(assigns) do
    ~H"""
    <div class="drive-list-header-cell" data-resizable-column={@field}>
      <button
        type="button"
        phx-click="toggle_sort"
        phx-value-field={@field}
        class={[
          "drive-list-header-button flex min-w-0 items-center gap-2 text-left transition hover:text-slate-700",
          active_sort?(@view.controls["sort"], @field) && "text-slate-700"
        ]}
      >
        <span>{@label}</span>
        <.icon name={sort_icon(@view.controls["sort"], @field)} class="size-4" />
      </button>
      <button
        type="button"
        class="drive-list-resizer"
        data-column-resizer={@field}
        data-min-width={@min}
        data-max-width={@max}
        aria-label={gettext("Resize %{column} column", column: @label)}
      >
      </button>
    </div>
    """
  end

  defp preview_icon(:folder), do: "hero-folder"
  defp preview_icon(:image), do: "hero-photo"
  defp preview_icon(:video), do: "hero-film"
  defp preview_icon(:file), do: "hero-document"

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

  defp entry_selection_key(%{kind: kind, id: id}), do: "#{kind}:#{id}"

  defp format_bytes(bytes) when is_integer(bytes) and bytes < 1024, do: "#{bytes} B"

  defp format_bytes(bytes) when is_integer(bytes) and bytes < 1_048_576,
    do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_bytes(bytes) when is_integer(bytes) and bytes < 1_073_741_824,
    do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_bytes(bytes) when is_integer(bytes),
    do: "#{Float.round(bytes / 1_073_741_824, 1)} GB"

  defp format_bytes(_), do: "--"

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
end
