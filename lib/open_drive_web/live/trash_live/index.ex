defmodule OpenDriveWeb.TrashLive.Index do
  use OpenDriveWeb, :live_view

  alias OpenDrive.Drive

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:confirm_empty_trash, false) |> load_trash()}
  end

  @impl true
  def handle_event("open_empty_trash_modal", _params, socket) do
    {:noreply, assign(socket, :confirm_empty_trash, true)}
  end

  def handle_event("cancel_empty_trash", _params, socket) do
    {:noreply, assign(socket, :confirm_empty_trash, false)}
  end

  def handle_event("empty_trash", _params, socket) do
    case Drive.empty_trash(socket.assigns.current_scope) do
      {:ok, result} ->
        message =
          gettext(
            "Trash emptied. %{files} file(s) and %{folders} folder(s) permanently deleted.",
            files: result.files_deleted,
            folders: result.folders_deleted
          )

        {:noreply,
         socket
         |> assign(:confirm_empty_trash, false)
         |> put_flash(:info, message)
         |> load_trash()}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:confirm_empty_trash, false)
         |> put_flash(:error, gettext("Unable to empty trash."))}
    end
  end

  def handle_event("restore_folder", %{"id" => id}, socket) do
    handle_restore(socket, {:folder, id})
  end

  def handle_event("restore_file", %{"id" => id}, socket) do
    handle_restore(socket, {:file, id})
  end

  defp handle_restore(socket, {kind, id}) do
    case Drive.restore_node(socket.assigns.current_scope, {kind, String.to_integer(id)}) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, gettext("Item restored.")) |> load_trash()}

      {:error, :name_conflict} ->
        {:noreply,
         put_flash(socket, :error, gettext("Restore failed because the name is already in use."))}
    end
  end

  defp load_trash(socket) do
    assign(socket,
      page_title: gettext("Trash"),
      trash: Drive.list_trash(socket.assigns.current_scope)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="grid gap-8 xl:grid-cols-[minmax(0,1.4fr)_minmax(320px,0.8fr)]">
        <div class="space-y-6">
          <div class="relative overflow-hidden rounded-[2rem] border border-white/70 bg-white/90 p-6 shadow-[0_30px_90px_rgba(15,23,42,0.12)] ring-1 ring-slate-200/70 backdrop-blur sm:p-8">
            <div class="pointer-events-none absolute inset-x-0 top-0 h-32 bg-[linear-gradient(135deg,rgba(244,63,94,0.14),rgba(14,165,233,0.08),rgba(255,255,255,0))]" />
            <div class="relative space-y-6">
              <div class="flex flex-wrap items-start justify-between gap-4">
                <div class="space-y-3">
                  <span class="inline-flex items-center rounded-full border border-rose-200 bg-rose-50 px-3 py-1 text-[0.7rem] font-semibold uppercase tracking-[0.32em] text-rose-700">
                    {gettext("Retention Zone")}
                  </span>
                  <div class="space-y-2">
                    <h1 class="max-w-2xl text-3xl font-black tracking-tight text-slate-950 sm:text-4xl">
                      {gettext("Organized trash to recover quickly and delete with clarity.")}
                    </h1>
                    <p class="max-w-2xl text-sm leading-7 text-slate-600 sm:text-base">
                      {gettext(
                        "Review removed items before final disposal. Everything here can still return to the workspace until you empty the trash."
                      )}
                    </p>
                  </div>
                </div>

                <div class="rounded-3xl border border-rose-900/20 bg-slate-950 px-4 py-4 text-white shadow-[0_18px_50px_rgba(15,23,42,0.22)]">
                  <p class="text-[0.68rem] font-semibold uppercase tracking-[0.28em] text-slate-300">
                    {gettext("Current status")}
                  </p>
                  <p class="mt-2 text-sm font-semibold">{trash_status(@trash)}</p>
                  <p class="mt-1 text-xs leading-5 text-slate-300">
                    {gettext("%{count} item(s) awaiting restore or permanent removal.",
                      count: trash_total(@trash)
                    )}
                  </p>
                </div>
              </div>

              <div class="grid gap-4 sm:grid-cols-3">
                <div class="rounded-3xl border border-slate-200 bg-slate-50/90 p-4">
                  <p class="text-[0.68rem] font-semibold uppercase tracking-[0.28em] text-slate-500">
                    {gettext("Folders")}
                  </p>
                  <p class="mt-2 text-2xl font-black tracking-tight text-slate-950">
                    {length(@trash.folders)}
                  </p>
                  <p class="mt-1 text-sm text-slate-600">
                    {gettext("Complete structures ready to restore.")}
                  </p>
                </div>
                <div class="rounded-3xl border border-slate-200 bg-slate-50/90 p-4">
                  <p class="text-[0.68rem] font-semibold uppercase tracking-[0.28em] text-slate-500">
                    {gettext("Files")}
                  </p>
                  <p class="mt-2 text-2xl font-black tracking-tight text-slate-950">
                    {length(@trash.files)}
                  </p>
                  <p class="mt-1 text-sm text-slate-600">
                    {gettext("Standalone documents still recoverable.")}
                  </p>
                </div>
                <div class="rounded-3xl border border-rose-200 bg-rose-50/90 p-4">
                  <p class="text-[0.68rem] font-semibold uppercase tracking-[0.28em] text-rose-700">
                    {gettext("Final action")}
                  </p>
                  <p class="mt-2 text-sm font-semibold text-slate-900">
                    {gettext("Permanent cleanup only when you are sure")}
                  </p>
                </div>
              </div>

              <div class="flex flex-wrap items-center justify-between gap-3 border-t border-slate-200 pt-5">
                <p class="max-w-2xl text-sm leading-6 text-slate-500">
                  {gettext(
                    "Restoring preserves the item context. Emptying the trash removes the records and also deletes the objects from storage."
                  )}
                </p>
                <button
                  type="button"
                  phx-click="open_empty_trash_modal"
                  class="inline-flex h-12 items-center justify-center rounded-2xl bg-rose-600 px-6 text-sm font-semibold text-white shadow-[0_18px_40px_rgba(225,29,72,0.28)] transition hover:-translate-y-0.5 hover:bg-rose-700 disabled:cursor-not-allowed disabled:bg-rose-200 disabled:shadow-none"
                  disabled={trash_empty?(@trash)}
                >
                  <.icon name="hero-trash" class="mr-2 size-4" /> {gettext("Empty trash")}
                </button>
              </div>
            </div>
          </div>

          <div class="grid gap-6 lg:grid-cols-2">
            <section class="rounded-[2rem] border border-white/80 bg-white/95 p-6 shadow-[0_24px_80px_rgba(15,23,42,0.10)] ring-1 ring-slate-200/70 backdrop-blur sm:p-8">
              <div class="mb-6 flex items-start justify-between gap-4">
                <div>
                  <p class="text-[0.72rem] font-semibold uppercase tracking-[0.3em] text-slate-500">
                    {gettext("Removed folders")}
                  </p>
                  <h2 class="mt-2 text-2xl font-bold tracking-tight text-slate-950">
                    {gettext("Entire structures ready to return")}
                  </h2>
                  <p class="mt-2 text-sm leading-6 text-slate-600">
                    {gettext("Restore the folder to return its hierarchy to the workspace.")}
                  </p>
                </div>
                <div class="hidden rounded-2xl border border-sky-200 bg-sky-50 px-3 py-2 text-xs font-semibold text-sky-800 sm:block">
                  {gettext("%{count} item(s)", count: length(@trash.folders))}
                </div>
              </div>

              <div class="space-y-3">
                <%= if Enum.empty?(@trash.folders) do %>
                  <div class="rounded-3xl border border-dashed border-slate-300 bg-slate-50/80 px-5 py-10 text-center">
                    <div class="mx-auto flex size-14 items-center justify-center rounded-3xl bg-white shadow-sm ring-1 ring-slate-200">
                      <.icon name="hero-folder" class="size-7 text-slate-400" />
                    </div>
                    <h3 class="mt-4 text-lg font-semibold text-slate-900">
                      {gettext("No folders in trash")}
                    </h3>
                    <p class="mt-2 text-sm leading-6 text-slate-500">
                      {gettext(
                        "When a folder is removed, it will appear here with the option to restore it."
                      )}
                    </p>
                  </div>
                <% else %>
                  <%= for folder <- @trash.folders do %>
                    <div class="flex flex-col gap-4 rounded-3xl border border-slate-200 bg-slate-50/70 p-4 transition hover:border-slate-300 hover:bg-white sm:flex-row sm:items-center sm:justify-between">
                      <div class="flex items-start gap-4">
                        <div class="flex size-12 items-center justify-center rounded-2xl bg-white text-sky-700 shadow-sm ring-1 ring-slate-200">
                          <.icon name="hero-folder" class="size-6" />
                        </div>
                        <div>
                          <p class="text-sm font-semibold text-slate-950">{folder.name}</p>
                          <p class="mt-1 text-sm text-slate-500">
                            {gettext("Folder removed and awaiting restore.")}
                          </p>
                        </div>
                      </div>

                      <button
                        phx-click="restore_folder"
                        phx-value-id={folder.id}
                        class="inline-flex h-11 items-center justify-center rounded-2xl border border-slate-200 bg-white px-4 text-sm font-semibold text-slate-700 transition hover:-translate-y-0.5 hover:border-sky-200 hover:text-sky-700"
                      >
                        <.icon name="hero-arrow-path" class="mr-2 size-4" /> {gettext("Restore")}
                      </button>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </section>

            <section class="rounded-[2rem] border border-white/80 bg-white/95 p-6 shadow-[0_24px_80px_rgba(15,23,42,0.10)] ring-1 ring-slate-200/70 backdrop-blur sm:p-8">
              <div class="mb-6 flex items-start justify-between gap-4">
                <div>
                  <p class="text-[0.72rem] font-semibold uppercase tracking-[0.3em] text-slate-500">
                    {gettext("Removed files")}
                  </p>
                  <h2 class="mt-2 text-2xl font-bold tracking-tight text-slate-950">
                    {gettext("Standalone documents still recoverable")}
                  </h2>
                  <p class="mt-2 text-sm leading-6 text-slate-600">
                    {gettext(
                      "Ideal for recovering a specific item without touching the rest of the structure."
                    )}
                  </p>
                </div>
                <div class="hidden rounded-2xl border border-amber-200 bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800 sm:block">
                  {gettext("%{count} item(s)", count: length(@trash.files))}
                </div>
              </div>

              <div class="space-y-3">
                <%= if Enum.empty?(@trash.files) do %>
                  <div class="rounded-3xl border border-dashed border-slate-300 bg-slate-50/80 px-5 py-10 text-center">
                    <div class="mx-auto flex size-14 items-center justify-center rounded-3xl bg-white shadow-sm ring-1 ring-slate-200">
                      <.icon name="hero-document" class="size-7 text-slate-400" />
                    </div>
                    <h3 class="mt-4 text-lg font-semibold text-slate-900">
                      {gettext("No files in trash")}
                    </h3>
                    <p class="mt-2 text-sm leading-6 text-slate-500">
                      {gettext("Files removed individually will appear here for quick restore.")}
                    </p>
                  </div>
                <% else %>
                  <%= for file <- @trash.files do %>
                    <div class="flex flex-col gap-4 rounded-3xl border border-slate-200 bg-slate-50/70 p-4 transition hover:border-slate-300 hover:bg-white sm:flex-row sm:items-center sm:justify-between">
                      <div class="flex items-start gap-4">
                        <div class="flex size-12 items-center justify-center rounded-2xl bg-white text-amber-600 shadow-sm ring-1 ring-slate-200">
                          <.icon name="hero-document" class="size-6" />
                        </div>
                        <div>
                          <p class="text-sm font-semibold text-slate-950">{file.name}</p>
                          <p class="mt-1 text-sm text-slate-500">
                            {gettext("File removed and kept until permanent cleanup.")}
                          </p>
                        </div>
                      </div>

                      <button
                        phx-click="restore_file"
                        phx-value-id={file.id}
                        class="inline-flex h-11 items-center justify-center rounded-2xl border border-slate-200 bg-white px-4 text-sm font-semibold text-slate-700 transition hover:-translate-y-0.5 hover:border-sky-200 hover:text-sky-700"
                      >
                        <.icon name="hero-arrow-path" class="mr-2 size-4" /> {gettext("Restore")}
                      </button>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </section>
          </div>
        </div>

        <aside class="space-y-6">
          <section class="rounded-[2rem] border border-slate-200/80 bg-slate-950 p-6 text-white shadow-[0_24px_80px_rgba(15,23,42,0.18)] sm:p-7">
            <p class="text-[0.72rem] font-semibold uppercase tracking-[0.3em] text-slate-400">
              {gettext("Trash policy")}
            </p>
            <h2 class="mt-3 text-2xl font-bold tracking-tight">
              {gettext("Recovery first, deletion only in the final step.")}
            </h2>
            <p class="mt-3 text-sm leading-6 text-slate-300">
              {gettext(
                "This area separates what can still be restored from what will be removed forever. The goal is to reduce human error in irreversible actions."
              )}
            </p>

            <div class="mt-6 space-y-3">
              <div class="rounded-3xl border border-white/10 bg-white/5 p-4">
                <p class="text-sm font-semibold">{gettext("Immediate restore")}</p>
                <p class="mt-1 text-sm leading-6 text-slate-300">
                  {gettext("Folders and files return individually to the workspace.")}
                </p>
              </div>
              <div class="rounded-3xl border border-white/10 bg-white/5 p-4">
                <p class="text-sm font-semibold">{gettext("Cleanup also deletes from storage")}</p>
                <p class="mt-1 text-sm leading-6 text-slate-300">
                  {gettext("After confirmation, the objects are no longer available for recovery.")}
                </p>
              </div>
            </div>
          </section>

          <section class="rounded-[2rem] border border-white/80 bg-white/95 p-6 shadow-[0_24px_80px_rgba(15,23,42,0.10)] ring-1 ring-slate-200/70 sm:p-7">
            <p class="text-[0.72rem] font-semibold uppercase tracking-[0.3em] text-slate-500">
              {gettext("Before emptying")}
            </p>
            <ul class="mt-4 space-y-4 text-sm leading-6 text-slate-600">
              <li class="flex gap-3">
                <span class="mt-1 size-2 rounded-full bg-rose-500" />
                {gettext("Review conflicting names before restoring important items.")}
              </li>
              <li class="flex gap-3">
                <span class="mt-1 size-2 rounded-full bg-rose-500" />
                {gettext("Use the trash as a review step, not as permanent storage.")}
              </li>
              <li class="flex gap-3">
                <span class="mt-1 size-2 rounded-full bg-rose-500" />
                {gettext("Only empty it when you are sure nothing needs to return to the workspace.")}
              </li>
            </ul>
          </section>
        </aside>

        <%= if @confirm_empty_trash do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/75 p-4 backdrop-blur-sm">
            <button
              type="button"
              phx-click="cancel_empty_trash"
              class="absolute inset-0 cursor-default"
              aria-label={gettext("Close empty trash modal")}
            >
            </button>
            <div class="relative z-10 w-full max-w-lg overflow-hidden rounded-[2rem] border border-white/70 bg-white/95 shadow-[0_30px_100px_rgba(15,23,42,0.25)] ring-1 ring-slate-200/70 backdrop-blur">
              <div class="relative border-b border-slate-200 px-6 py-5">
                <div class="pointer-events-none absolute inset-x-0 top-0 h-24 bg-[linear-gradient(135deg,rgba(244,63,94,0.14),rgba(255,255,255,0))]" />
                <div class="relative">
                  <p class="text-xs font-semibold uppercase tracking-[0.24em] text-rose-600">
                    {gettext("Empty trash")}
                  </p>
                  <h2 class="mt-2 text-2xl font-bold tracking-tight text-slate-950">
                    {gettext("Delete permanently?")}
                  </h2>
                  <p class="mt-2 text-sm text-slate-500">
                    {gettext(
                      "This action permanently removes the files from the trash and deletes the objects from storage."
                    )}
                  </p>
                </div>
              </div>

              <div class="space-y-5 px-6 py-6">
                <div class="rounded-3xl border border-rose-100 bg-rose-50/80 px-4 py-4 text-sm text-slate-600">
                  <p class="text-[0.68rem] font-semibold uppercase tracking-[0.28em] text-rose-700">
                    {gettext("Impact of this action")}
                  </p>
                  <p class="mt-2">
                    {gettext("%{files} file(s) and %{folders} folder(s) will be permanently removed.",
                      files: length(@trash.files),
                      folders: length(@trash.folders)
                    )}
                  </p>
                </div>

                <div class="flex items-center justify-end gap-3">
                  <button
                    type="button"
                    phx-click="cancel_empty_trash"
                    class="rounded-xl px-4 py-2.5 text-sm font-medium text-slate-500 transition hover:bg-slate-100"
                  >
                    {gettext("Cancel")}
                  </button>
                  <button
                    type="button"
                    phx-click="empty_trash"
                    class="rounded-xl bg-rose-600 px-4 py-2.5 text-sm font-semibold text-white shadow-[0_18px_40px_rgba(225,29,72,0.28)] transition hover:bg-rose-700"
                  >
                    Limpar lixeira
                  </button>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  defp trash_total(trash) do
    length(trash.folders) + length(trash.files)
  end

  defp trash_empty?(trash) do
    trash_total(trash) == 0
  end

  defp trash_status(trash) do
    if trash_empty?(trash), do: "Lixeira vazia", else: "Itens aguardando decisão"
  end
end
