defmodule OpenDriveWeb.MembersLive.Index do
  use OpenDriveWeb, :live_view

  alias OpenDrive.Tenancy

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:member_form, to_form(%{"email" => "", "role" => "member"}, as: "member"))
     |> load_members()}
  end

  @impl true
  def handle_event("add_member", %{"member" => attrs}, socket) do
    case Tenancy.add_member(
           socket.assigns.current_scope,
           socket.assigns.current_scope.tenant,
           attrs
         ) do
      {:ok, _membership} ->
        {:noreply, socket |> put_flash(:info, "Member added.") |> load_members()}

      {:error, :user_not_found} ->
        {:noreply,
         put_flash(socket, :error, "User must register before being added to this workspace.")}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "Only owners/admins can manage members.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add member.")}
    end
  end

  defp load_members(socket) do
    assign(socket,
      page_title: "Members",
      memberships: Tenancy.list_members(socket.assigns.current_scope)
    )
  end

  defp membership_total(memberships), do: length(memberships)

  defp role_total(memberships, role) do
    Enum.count(memberships, &(&1.role == role))
  end

  defp member_status(memberships) do
    if Enum.empty?(memberships), do: "Workspace sem membros", else: "Equipe ativa"
  end

  defp role_badge("owner"),
    do: "border-amber-200 bg-amber-50 text-amber-800"

  defp role_badge("admin"),
    do: "border-sky-200 bg-sky-50 text-sky-800"

  defp role_badge(_role),
    do: "border-slate-200 bg-slate-100 text-slate-700"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="grid gap-8 xl:grid-cols-[minmax(0,1.4fr)_minmax(320px,0.8fr)]">
        <div class="space-y-6">
          <div class="relative overflow-hidden rounded-[2rem] border border-white/70 bg-white/90 p-6 shadow-[0_30px_90px_rgba(15,23,42,0.12)] ring-1 ring-slate-200/70 backdrop-blur sm:p-8">
            <div class="pointer-events-none absolute inset-x-0 top-0 h-32 bg-[linear-gradient(135deg,rgba(14,165,233,0.14),rgba(16,185,129,0.10),rgba(255,255,255,0))]" />
            <div class="relative space-y-6">
              <div class="flex flex-wrap items-start justify-between gap-4">
                <div class="space-y-3">
                  <span class="inline-flex items-center rounded-full border border-sky-200 bg-sky-50 px-3 py-1 text-[0.7rem] font-semibold uppercase tracking-[0.32em] text-sky-700">
                    Team Access
                  </span>
                  <div class="space-y-2">
                    <h1 class="max-w-2xl text-3xl font-black tracking-tight text-slate-950 sm:text-4xl">
                      Membros com contexto claro para administrar o workspace sem ruído.
                    </h1>
                    <p class="max-w-2xl text-sm leading-7 text-slate-600 sm:text-base">
                      Centralize quem participa do ambiente, identifique rapidamente os perfis de acesso e convide novas pessoas sem perder o controle operacional.
                    </p>
                  </div>
                </div>

                <div class="rounded-3xl border border-emerald-900/20 bg-slate-950 px-4 py-4 text-white shadow-[0_18px_50px_rgba(15,23,42,0.22)]">
                  <p class="text-[0.68rem] font-semibold uppercase tracking-[0.28em] text-slate-300">
                    Status atual
                  </p>
                  <p class="mt-2 text-sm font-semibold">{member_status(@memberships)}</p>
                  <p class="mt-1 text-xs leading-5 text-slate-300">
                    {membership_total(@memberships)} pessoa(s) com acesso ao workspace.
                  </p>
                </div>
              </div>

              <div class="grid gap-4 sm:grid-cols-3">
                <div class="rounded-3xl border border-slate-200 bg-slate-50/90 p-4">
                  <p class="text-[0.68rem] font-semibold uppercase tracking-[0.28em] text-slate-500">
                    Total
                  </p>
                  <p class="mt-2 text-2xl font-black tracking-tight text-slate-950">
                    {membership_total(@memberships)}
                  </p>
                  <p class="mt-1 text-sm text-slate-600">
                    Pessoas ativas neste tenant.
                  </p>
                </div>
                <div class="rounded-3xl border border-slate-200 bg-slate-50/90 p-4">
                  <p class="text-[0.68rem] font-semibold uppercase tracking-[0.28em] text-slate-500">
                    Admins
                  </p>
                  <p class="mt-2 text-2xl font-black tracking-tight text-slate-950">
                    {role_total(@memberships, "admin") + role_total(@memberships, "owner")}
                  </p>
                  <p class="mt-1 text-sm text-slate-600">
                    Perfis com poder de gestão.
                  </p>
                </div>
                <div class="rounded-3xl border border-emerald-200 bg-emerald-50/90 p-4">
                  <p class="text-[0.68rem] font-semibold uppercase tracking-[0.28em] text-emerald-700">
                    Colaboração
                  </p>
                  <p class="mt-2 text-sm font-semibold text-slate-900">
                    Convites para usuários já cadastrados no OpenDrive
                  </p>
                </div>
              </div>
            </div>
          </div>

          <section class="rounded-[2rem] border border-white/80 bg-white/95 p-6 shadow-[0_24px_80px_rgba(15,23,42,0.10)] ring-1 ring-slate-200/70 backdrop-blur sm:p-8">
            <div class="mb-6 flex items-start justify-between gap-4">
              <div>
                <p class="text-[0.72rem] font-semibold uppercase tracking-[0.3em] text-slate-500">
                  Directory
                </p>
                <h2 class="mt-2 text-2xl font-bold tracking-tight text-slate-950">
                  Pessoas e níveis de acesso visíveis de imediato
                </h2>
                <p class="mt-2 max-w-2xl text-sm leading-6 text-slate-600">
                  A lista abaixo destaca quem administra o ambiente e quem participa da operação diária.
                </p>
              </div>
              <div class="hidden rounded-2xl border border-sky-200 bg-sky-50 px-3 py-2 text-xs font-semibold text-sky-800 sm:block">
                {membership_total(@memberships)} membro(s)
              </div>
            </div>

            <div class="space-y-3">
              <%= if Enum.empty?(@memberships) do %>
                <div class="rounded-3xl border border-dashed border-slate-300 bg-slate-50/80 px-5 py-10 text-center">
                  <div class="mx-auto flex size-14 items-center justify-center rounded-3xl bg-white shadow-sm ring-1 ring-slate-200">
                    <.icon name="hero-users" class="size-7 text-slate-400" />
                  </div>
                  <h3 class="mt-4 text-lg font-semibold text-slate-900">
                    Nenhum membro encontrado
                  </h3>
                  <p class="mt-2 text-sm leading-6 text-slate-500">
                    Adicione usuários já cadastrados para começar a compartilhar este workspace.
                  </p>
                </div>
              <% else %>
                <%= for membership <- @memberships do %>
                  <div class="flex flex-col gap-4 rounded-3xl border border-slate-200 bg-slate-50/70 p-4 transition hover:border-slate-300 hover:bg-white sm:flex-row sm:items-center sm:justify-between">
                    <div class="flex items-start gap-4">
                      <div class="flex size-12 items-center justify-center rounded-2xl bg-white text-sky-700 shadow-sm ring-1 ring-slate-200">
                        <.icon name="hero-user-circle" class="size-6" />
                      </div>
                      <div>
                        <p class="text-sm font-semibold text-slate-950">{membership.user.email}</p>
                        <p class="mt-1 text-sm text-slate-500">
                          <%= if membership.role in ["owner", "admin"] do %>
                            Pode administrar membros e operar o workspace.
                          <% else %>
                            Participa do workspace com acesso operacional padrão.
                          <% end %>
                        </p>
                      </div>
                    </div>

                    <div class={[
                      "inline-flex items-center rounded-2xl border px-3 py-2 text-xs font-semibold uppercase tracking-[0.24em]",
                      role_badge(membership.role)
                    ]}>
                      {membership.role}
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
          </section>
        </div>

        <aside class="rounded-[2rem] border border-white/80 bg-white/95 p-6 shadow-[0_24px_80px_rgba(15,23,42,0.10)] ring-1 ring-slate-200/70 backdrop-blur sm:p-8">
          <div class="space-y-4">
            <div>
              <p class="text-[0.72rem] font-semibold uppercase tracking-[0.3em] text-slate-500">
                Access Control
              </p>
              <h2 class="mt-2 text-2xl font-bold tracking-tight text-slate-950">
                Adicionar novo membro
              </h2>
              <p class="mt-2 text-sm leading-6 text-slate-600">
                Convide uma pessoa pelo email já registrado e defina o nível de responsabilidade inicial.
              </p>
            </div>

            <div class="rounded-3xl border border-slate-200 bg-slate-50/80 p-4">
              <p class="text-[0.68rem] font-semibold uppercase tracking-[0.28em] text-slate-500">
                Regra de acesso
              </p>
              <p class="mt-2 text-sm leading-6 text-slate-600">
                Apenas owners e admins conseguem gerenciar membros deste workspace.
              </p>
            </div>

            <.form
              :if={OpenDrive.Accounts.Scope.manage_members?(@current_scope)}
              for={@member_form}
              phx-submit="add_member"
              class="space-y-4"
            >
              <.input field={@member_form[:email]} type="email" label="User email" required />
              <.input
                field={@member_form[:role]}
                type="select"
                label="Role"
                options={[{"Admin", "admin"}, {"Member", "member"}]}
              />
              <button
                type="submit"
                class="inline-flex h-12 w-full items-center justify-center rounded-2xl bg-sky-600 px-6 text-sm font-semibold text-white shadow-[0_18px_40px_rgba(2,132,199,0.24)] transition hover:-translate-y-0.5 hover:bg-sky-700"
              >
                <.icon name="hero-user-plus" class="mr-2 size-4" /> Add member
              </button>
            </.form>

            <div
              :if={!OpenDrive.Accounts.Scope.manage_members?(@current_scope)}
              class="rounded-3xl border border-amber-200 bg-amber-50/90 p-4"
            >
              <p class="text-sm font-semibold text-amber-900">Permissão insuficiente</p>
              <p class="mt-2 text-sm leading-6 text-amber-800">
                Seu perfil atual pode visualizar a equipe, mas não pode adicionar novos membros.
              </p>
            </div>
          </div>
        </aside>
      </section>
    </Layouts.app>
    """
  end
end
