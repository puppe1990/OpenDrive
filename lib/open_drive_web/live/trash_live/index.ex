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
          "Trash emptied. #{result.files_deleted} file(s) and #{result.folders_deleted} folder(s) permanently deleted."

        {:noreply,
         socket
         |> assign(:confirm_empty_trash, false)
         |> put_flash(:info, message)
         |> load_trash()}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:confirm_empty_trash, false)
         |> put_flash(:error, "Unable to empty trash.")}
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
        {:noreply, socket |> put_flash(:info, "Item restored.") |> load_trash()}

      {:error, :name_conflict} ->
        {:noreply,
         put_flash(socket, :error, "Restore failed because the name is already in use.")}
    end
  end

  defp load_trash(socket) do
    assign(socket, page_title: "Trash", trash: Drive.list_trash(socket.assigns.current_scope))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="space-y-6">
        <div>
          <p class="text-sm uppercase tracking-[0.35em] text-slate-500">Retention</p>
          <h1 class="text-3xl font-black text-slate-950">Trash</h1>
        </div>

        <div class="flex justify-end">
          <button
            type="button"
            phx-click="open_empty_trash_modal"
            class="btn btn-error"
            disabled={Enum.empty?(@trash.folders) and Enum.empty?(@trash.files)}
          >
            Limpar lixeira
          </button>
        </div>

        <div class="grid gap-6 lg:grid-cols-2">
          <section class="rounded-[2rem] border border-slate-200 bg-white p-6 shadow-sm">
            <h2 class="mb-4 text-lg font-semibold text-slate-950">Folders</h2>
            <div class="space-y-3">
              <%= for folder <- @trash.folders do %>
                <div class="flex items-center justify-between rounded-2xl border border-slate-200 p-4">
                  <span>{folder.name}</span>
                  <button
                    phx-click="restore_folder"
                    phx-value-id={folder.id}
                    class="btn btn-outline btn-sm"
                  >
                    Restore
                  </button>
                </div>
              <% end %>
            </div>
          </section>

          <section class="rounded-[2rem] border border-slate-200 bg-white p-6 shadow-sm">
            <h2 class="mb-4 text-lg font-semibold text-slate-950">Files</h2>
            <div class="space-y-3">
              <%= for file <- @trash.files do %>
                <div class="flex items-center justify-between rounded-2xl border border-slate-200 p-4">
                  <span>{file.name}</span>
                  <button
                    phx-click="restore_file"
                    phx-value-id={file.id}
                    class="btn btn-outline btn-sm"
                  >
                    Restore
                  </button>
                </div>
              <% end %>
            </div>
          </section>
        </div>

        <%= if @confirm_empty_trash do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/70 p-4">
            <button
              type="button"
              phx-click="cancel_empty_trash"
              class="absolute inset-0 cursor-default"
              aria-label="Fechar modal de limpar lixeira"
            >
            </button>

            <div class="relative z-10 w-full max-w-lg overflow-hidden rounded-[2rem] bg-white shadow-2xl ring-1 ring-slate-200">
              <div class="border-b border-slate-200 px-6 py-5">
                <p class="text-xs font-semibold uppercase tracking-[0.24em] text-rose-600">
                  Limpar lixeira
                </p>
                <h2 class="mt-2 text-2xl font-bold tracking-tight text-slate-950">
                  Deletar permanentemente?
                </h2>
                <p class="mt-2 text-sm text-slate-500">
                  Esta acao remove os arquivos da lixeira em definitivo e apaga os objetos no storage.
                </p>
              </div>

              <div class="space-y-5 px-6 py-6">
                <div class="rounded-2xl bg-slate-50 px-4 py-3 text-sm text-slate-500 ring-1 ring-slate-200">
                  {length(@trash.files)} arquivo(s) e {length(@trash.folders)} pasta(s) serao removidos.
                </div>

                <div class="flex items-center justify-end gap-3">
                  <button
                    type="button"
                    phx-click="cancel_empty_trash"
                    class="rounded-xl px-4 py-2.5 text-sm font-medium text-slate-500 transition hover:bg-slate-100"
                  >
                    Cancelar
                  </button>
                  <button
                    type="button"
                    phx-click="empty_trash"
                    class="rounded-xl bg-rose-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-rose-700"
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
end
