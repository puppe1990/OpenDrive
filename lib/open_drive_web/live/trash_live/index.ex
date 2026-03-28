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
      <section class="grid gap-8 xl:grid-cols-[minmax(0,1.4fr)_minmax(320px,0.8fr)]">
        <div class="space-y-6">
          <div class="relative overflow-hidden rounded-[2rem] border border-white/70 bg-white/90 p-6 shadow-[0_30px_90px_rgba(15,23,42,0.12)] ring-1 ring-slate-200/70 backdrop-blur sm:p-8">
            <div class="pointer-events-none absolute inset-x-0 top-0 h-32 bg-[linear-gradient(135deg,rgba(244,63,94,0.14),rgba(14,165,233,0.08),rgba(255,255,255,0))]" />
            <div class="relative space-y-6">
              <div class="flex flex-wrap items-start justify-between gap-4">
                <div class="space-y-3">
                  <span class="inline-flex items-center rounded-full border border-rose-200 bg-rose-50 px-3 py-1 text-[0.7rem] font-semibold uppercase tracking-[0.32em] text-rose-700">
                    Retention Zone
                  </span>
                  <div class="space-y-2">
                    <h1 class="max-w-2xl text-3xl font-black tracking-tight text-slate-950 sm:text-4xl">
                      Lixeira organizada para recuperar rápido e apagar com clareza.
                    </h1>
                    <p class="max-w-2xl text-sm leading-7 text-slate-600 sm:text-base">
                      Revise itens removidos antes do descarte final. Tudo aqui ainda pode voltar ao workspace, até você limpar a lixeira.
                    </p>
                  </div>
                </div>

                <div class="rounded-3xl border border-rose-900/20 bg-slate-950 px-4 py-4 text-white shadow-[0_18px_50px_rgba(15,23,42,0.22)]">
                  <p class="text-[0.68rem] font-semibold uppercase tracking-[0.28em] text-slate-300">
                    Status atual
                  </p>
                  <p class="mt-2 text-sm font-semibold">{trash_status(@trash)}</p>
                  <p class="mt-1 text-xs leading-5 text-slate-300">
                    {trash_total(@trash)} item(ns) aguardando restauração ou remoção permanente.
                  </p>
                </div>
              </div>

              <div class="grid gap-4 sm:grid-cols-3">
                <div class="rounded-3xl border border-slate-200 bg-slate-50/90 p-4">
                  <p class="text-[0.68rem] font-semibold uppercase tracking-[0.28em] text-slate-500">
                    Pastas
                  </p>
                  <p class="mt-2 text-2xl font-black tracking-tight text-slate-950">
                    {length(@trash.folders)}
                  </p>
                  <p class="mt-1 text-sm text-slate-600">
                    Estruturas completas prontas para restaurar.
                  </p>
                </div>
                <div class="rounded-3xl border border-slate-200 bg-slate-50/90 p-4">
                  <p class="text-[0.68rem] font-semibold uppercase tracking-[0.28em] text-slate-500">
                    Arquivos
                  </p>
                  <p class="mt-2 text-2xl font-black tracking-tight text-slate-950">
                    {length(@trash.files)}
                  </p>
                  <p class="mt-1 text-sm text-slate-600">Documentos isolados ainda recuperáveis.</p>
                </div>
                <div class="rounded-3xl border border-rose-200 bg-rose-50/90 p-4">
                  <p class="text-[0.68rem] font-semibold uppercase tracking-[0.28em] text-rose-700">
                    Ação final
                  </p>
                  <p class="mt-2 text-sm font-semibold text-slate-900">
                    Limpeza permanente só quando tiver certeza
                  </p>
                </div>
              </div>

              <div class="flex flex-wrap items-center justify-between gap-3 border-t border-slate-200 pt-5">
                <p class="max-w-2xl text-sm leading-6 text-slate-500">
                  Restaurar preserva o contexto do item. Limpar a lixeira remove os registros e também apaga os objetos no storage.
                </p>
                <button
                  type="button"
                  phx-click="open_empty_trash_modal"
                  class="inline-flex h-12 items-center justify-center rounded-2xl bg-rose-600 px-6 text-sm font-semibold text-white shadow-[0_18px_40px_rgba(225,29,72,0.28)] transition hover:-translate-y-0.5 hover:bg-rose-700 disabled:cursor-not-allowed disabled:bg-rose-200 disabled:shadow-none"
                  disabled={trash_empty?(@trash)}
                >
                  <.icon name="hero-trash" class="mr-2 size-4" /> Limpar lixeira
                </button>
              </div>
            </div>
          </div>

          <div class="grid gap-6 lg:grid-cols-2">
            <section class="rounded-[2rem] border border-white/80 bg-white/95 p-6 shadow-[0_24px_80px_rgba(15,23,42,0.10)] ring-1 ring-slate-200/70 backdrop-blur sm:p-8">
              <div class="mb-6 flex items-start justify-between gap-4">
                <div>
                  <p class="text-[0.72rem] font-semibold uppercase tracking-[0.3em] text-slate-500">
                    Pastas removidas
                  </p>
                  <h2 class="mt-2 text-2xl font-bold tracking-tight text-slate-950">
                    Estruturas inteiras prontas para voltar
                  </h2>
                  <p class="mt-2 text-sm leading-6 text-slate-600">
                    Restaure a pasta para devolver sua hierarquia ao workspace.
                  </p>
                </div>
                <div class="hidden rounded-2xl border border-sky-200 bg-sky-50 px-3 py-2 text-xs font-semibold text-sky-800 sm:block">
                  {length(@trash.folders)} item(ns)
                </div>
              </div>

              <div class="space-y-3">
                <%= if Enum.empty?(@trash.folders) do %>
                  <div class="rounded-3xl border border-dashed border-slate-300 bg-slate-50/80 px-5 py-10 text-center">
                    <div class="mx-auto flex size-14 items-center justify-center rounded-3xl bg-white shadow-sm ring-1 ring-slate-200">
                      <.icon name="hero-folder" class="size-7 text-slate-400" />
                    </div>
                    <h3 class="mt-4 text-lg font-semibold text-slate-900">
                      Nenhuma pasta na lixeira
                    </h3>
                    <p class="mt-2 text-sm leading-6 text-slate-500">
                      Quando uma pasta for removida, ela aparecerá aqui com a opção de restauração.
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
                            Pasta removida e aguardando restauração.
                          </p>
                        </div>
                      </div>

                      <button
                        phx-click="restore_folder"
                        phx-value-id={folder.id}
                        class="inline-flex h-11 items-center justify-center rounded-2xl border border-slate-200 bg-white px-4 text-sm font-semibold text-slate-700 transition hover:-translate-y-0.5 hover:border-sky-200 hover:text-sky-700"
                      >
                        <.icon name="hero-arrow-path" class="mr-2 size-4" /> Restaurar
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
                    Arquivos removidos
                  </p>
                  <h2 class="mt-2 text-2xl font-bold tracking-tight text-slate-950">
                    Documentos soltos ainda recuperáveis
                  </h2>
                  <p class="mt-2 text-sm leading-6 text-slate-600">
                    Ideal para recuperar um item específico sem tocar no restante da estrutura.
                  </p>
                </div>
                <div class="hidden rounded-2xl border border-amber-200 bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800 sm:block">
                  {length(@trash.files)} item(ns)
                </div>
              </div>

              <div class="space-y-3">
                <%= if Enum.empty?(@trash.files) do %>
                  <div class="rounded-3xl border border-dashed border-slate-300 bg-slate-50/80 px-5 py-10 text-center">
                    <div class="mx-auto flex size-14 items-center justify-center rounded-3xl bg-white shadow-sm ring-1 ring-slate-200">
                      <.icon name="hero-document" class="size-7 text-slate-400" />
                    </div>
                    <h3 class="mt-4 text-lg font-semibold text-slate-900">
                      Nenhum arquivo na lixeira
                    </h3>
                    <p class="mt-2 text-sm leading-6 text-slate-500">
                      Arquivos removidos individualmente aparecerão aqui para restauração rápida.
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
                            Arquivo removido e mantido até a limpeza definitiva.
                          </p>
                        </div>
                      </div>

                      <button
                        phx-click="restore_file"
                        phx-value-id={file.id}
                        class="inline-flex h-11 items-center justify-center rounded-2xl border border-slate-200 bg-white px-4 text-sm font-semibold text-slate-700 transition hover:-translate-y-0.5 hover:border-sky-200 hover:text-sky-700"
                      >
                        <.icon name="hero-arrow-path" class="mr-2 size-4" /> Restaurar
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
              Política da lixeira
            </p>
            <h2 class="mt-3 text-2xl font-bold tracking-tight">
              Recuperação primeiro, exclusão só no passo final.
            </h2>
            <p class="mt-3 text-sm leading-6 text-slate-300">
              Esta área separa o que ainda pode ser restaurado do que será removido para sempre. O objetivo é reduzir erro humano em ações irreversíveis.
            </p>

            <div class="mt-6 space-y-3">
              <div class="rounded-3xl border border-white/10 bg-white/5 p-4">
                <p class="text-sm font-semibold">Restauração imediata</p>
                <p class="mt-1 text-sm leading-6 text-slate-300">
                  Pastas e arquivos voltam individualmente para o workspace.
                </p>
              </div>
              <div class="rounded-3xl border border-white/10 bg-white/5 p-4">
                <p class="text-sm font-semibold">Limpeza apaga também no storage</p>
                <p class="mt-1 text-sm leading-6 text-slate-300">
                  Depois da confirmação, os objetos não continuam disponíveis para recuperação.
                </p>
              </div>
            </div>
          </section>

          <section class="rounded-[2rem] border border-white/80 bg-white/95 p-6 shadow-[0_24px_80px_rgba(15,23,42,0.10)] ring-1 ring-slate-200/70 sm:p-7">
            <p class="text-[0.72rem] font-semibold uppercase tracking-[0.3em] text-slate-500">
              Antes de limpar
            </p>
            <ul class="mt-4 space-y-4 text-sm leading-6 text-slate-600">
              <li class="flex gap-3">
                <span class="mt-1 size-2 rounded-full bg-rose-500" />
                Revise nomes conflitantes antes de restaurar itens importantes.
              </li>
              <li class="flex gap-3">
                <span class="mt-1 size-2 rounded-full bg-rose-500" />
                Use a lixeira como etapa de revisão, não como arquivo permanente.
              </li>
              <li class="flex gap-3">
                <span class="mt-1 size-2 rounded-full bg-rose-500" />
                Só execute a limpeza quando tiver certeza de que nada precisa voltar ao workspace.
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
              aria-label="Fechar modal de limpar lixeira"
            >
            </button>
            <div class="relative z-10 w-full max-w-lg overflow-hidden rounded-[2rem] border border-white/70 bg-white/95 shadow-[0_30px_100px_rgba(15,23,42,0.25)] ring-1 ring-slate-200/70 backdrop-blur">
              <div class="relative border-b border-slate-200 px-6 py-5">
                <div class="pointer-events-none absolute inset-x-0 top-0 h-24 bg-[linear-gradient(135deg,rgba(244,63,94,0.14),rgba(255,255,255,0))]" />
                <div class="relative">
                  <p class="text-xs font-semibold uppercase tracking-[0.24em] text-rose-600">
                    Limpar lixeira
                  </p>
                  <h2 class="mt-2 text-2xl font-bold tracking-tight text-slate-950">
                    Deletar permanentemente?
                  </h2>
                  <p class="mt-2 text-sm text-slate-500">
                    Esta ação remove os arquivos da lixeira em definitivo e apaga os objetos no storage.
                  </p>
                </div>
              </div>

              <div class="space-y-5 px-6 py-6">
                <div class="rounded-3xl border border-rose-100 bg-rose-50/80 px-4 py-4 text-sm text-slate-600">
                  <p class="text-[0.68rem] font-semibold uppercase tracking-[0.28em] text-rose-700">
                    Impacto desta ação
                  </p>
                  <p class="mt-2">
                    {length(@trash.files)} arquivo(s) e {length(@trash.folders)} pasta(s) serão removidos de forma permanente.
                  </p>
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
