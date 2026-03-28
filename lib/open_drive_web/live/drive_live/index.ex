defmodule OpenDriveWeb.DriveLive.Index do
  use OpenDriveWeb, :live_view

  alias OpenDrive.Drive

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> allow_upload(:files, accept: :any, max_entries: 5)
      |> assign(:folder_form, to_form(%{"name" => ""}, as: "folder"))

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

  def handle_event("upload", _params, socket) do
    results =
      consume_uploaded_entries(socket, :files, fn %{path: path}, entry ->
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

    error? = Enum.any?(results, &match?({:error, _}, &1))

    socket =
      if error?,
        do: put_flash(socket, :error, "Upload failed for at least one file."),
        else: put_flash(socket, :info, "Upload complete.")

    {:noreply, load_drive(socket, socket.assigns.current_folder_id)}
  end

  def handle_event("delete_folder", %{"id" => id}, socket) do
    {:ok, _} = Drive.soft_delete_node(socket.assigns.current_scope, {:folder, id})
    {:noreply, load_drive(socket, socket.assigns.current_folder_id)}
  end

  def handle_event("delete_file", %{"id" => id}, socket) do
    {:ok, _} = Drive.soft_delete_node(socket.assigns.current_scope, {:file, id})
    {:noreply, load_drive(socket, socket.assigns.current_folder_id)}
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
  end

  defp normalize_id(id) when is_binary(id), do: String.to_integer(id)
  defp normalize_id(id), do: id

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="space-y-8">
        <div class="flex flex-wrap items-center justify-between gap-4">
          <div>
            <p class="text-sm uppercase tracking-[0.35em] text-slate-500">Workspace</p>
            <h1 class="text-3xl font-black text-slate-950">{@current_scope.tenant.name}</h1>
          </div>
          <div class="text-sm text-slate-500">{@current_scope.user.email}</div>
        </div>

        <nav class="flex flex-wrap items-center gap-2 text-sm">
          <.link navigate={~p"/app"} class="rounded-full bg-white px-4 py-2 shadow-sm">Root</.link>
          <%= for folder <- @breadcrumbs do %>
            <span>/</span>
            <.link
              navigate={~p"/app/folders/#{folder.id}"}
              class="rounded-full bg-white px-4 py-2 shadow-sm"
            >
              {folder.name}
            </.link>
          <% end %>
        </nav>

        <div class="grid gap-6 xl:grid-cols-[320px_minmax(0,1fr)]">
          <aside class="space-y-6 rounded-[2rem] border border-slate-200 bg-white p-6 shadow-sm">
            <div class="space-y-3">
              <p class="text-sm font-semibold text-slate-700">New folder</p>
              <.form for={@folder_form} phx-submit="create_folder" class="space-y-3">
                <.input field={@folder_form[:name]} type="text" label="Folder name" required />
                <.button class="btn btn-primary w-full">Create folder</.button>
              </.form>
            </div>

            <div class="space-y-3">
              <p class="text-sm font-semibold text-slate-700">Upload files</p>
              <.live_file_input upload={@uploads.files} class="file-input file-input-bordered w-full" />
              <.button phx-click="upload" class="btn btn-outline w-full">Upload</.button>
            </div>
          </aside>

          <div class="space-y-6">
            <section class="rounded-[2rem] border border-slate-200 bg-white p-6 shadow-sm">
              <div class="mb-4 flex items-center justify-between">
                <h2 class="text-lg font-semibold text-slate-950">Folders</h2>
                <span class="text-sm text-slate-500">{length(@children.folders)} items</span>
              </div>
              <div class="grid gap-4 md:grid-cols-2">
                <%= for folder <- @children.folders do %>
                  <div class="rounded-2xl border border-slate-200 p-4">
                    <.link
                      navigate={~p"/app/folders/#{folder.id}"}
                      class="text-lg font-semibold text-slate-950 hover:text-sky-700"
                    >
                      {folder.name}
                    </.link>
                    <button
                      phx-click="delete_folder"
                      phx-value-id={folder.id}
                      class="mt-4 text-sm text-rose-600"
                    >
                      Move to trash
                    </button>
                  </div>
                <% end %>
              </div>
            </section>

            <section class="rounded-[2rem] border border-slate-200 bg-white p-6 shadow-sm">
              <div class="mb-4 flex items-center justify-between">
                <h2 class="text-lg font-semibold text-slate-950">Files</h2>
                <span class="text-sm text-slate-500">{length(@children.files)} items</span>
              </div>
              <div class="space-y-3">
                <%= for file <- @children.files do %>
                  <div class="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-slate-200 p-4">
                    <div>
                      <p class="font-semibold text-slate-950">{file.name}</p>
                      <p class="text-sm text-slate-500">
                        {file.file_object.content_type} · {file.file_object.size} bytes
                      </p>
                    </div>
                    <div class="flex items-center gap-3">
                      <.link href={~p"/app/files/#{file.id}/download"} class="btn btn-ghost btn-sm">
                        Download
                      </.link>
                      <button
                        phx-click="delete_file"
                        phx-value-id={file.id}
                        class="btn btn-ghost btn-sm text-rose-600"
                      >
                        Trash
                      </button>
                    </div>
                  </div>
                <% end %>
              </div>
            </section>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
