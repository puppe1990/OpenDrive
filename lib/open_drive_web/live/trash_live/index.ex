defmodule OpenDriveWeb.TrashLive.Index do
  use OpenDriveWeb, :live_view

  alias OpenDrive.Drive

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load_trash(socket)}
  end

  @impl true
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
      </section>
    </Layouts.app>
    """
  end
end
