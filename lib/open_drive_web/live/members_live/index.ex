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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="grid gap-6 xl:grid-cols-[340px_minmax(0,1fr)]">
        <aside class="rounded-[2rem] border border-slate-200 bg-white p-6 shadow-sm">
          <h1 class="text-2xl font-black text-slate-950">Members</h1>
          <p class="mt-2 text-sm text-slate-500">Add existing OpenDrive users to this workspace.</p>

          <.form
            :if={OpenDrive.Accounts.Scope.manage_members?(@current_scope)}
            for={@member_form}
            phx-submit="add_member"
            class="mt-6 space-y-4"
          >
            <.input field={@member_form[:email]} type="email" label="User email" required />
            <.input
              field={@member_form[:role]}
              type="select"
              label="Role"
              options={[{"Admin", "admin"}, {"Member", "member"}]}
            />
            <.button class="btn btn-primary w-full">Add member</.button>
          </.form>
        </aside>

        <section class="rounded-[2rem] border border-slate-200 bg-white p-6 shadow-sm">
          <div class="space-y-3">
            <%= for membership <- @memberships do %>
              <div class="flex items-center justify-between rounded-2xl border border-slate-200 p-4">
                <div>
                  <p class="font-semibold text-slate-950">{membership.user.email}</p>
                  <p class="text-sm uppercase tracking-[0.25em] text-slate-500">{membership.role}</p>
                </div>
              </div>
            <% end %>
          </div>
        </section>
      </section>
    </Layouts.app>
    """
  end
end
