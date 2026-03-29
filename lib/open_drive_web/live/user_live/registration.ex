defmodule OpenDriveWeb.UserLive.Registration do
  use OpenDriveWeb, :live_view

  alias OpenDrive.Accounts
  alias OpenDrive.Accounts.User
  alias OpenDriveWeb.UserAuth

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="mx-auto grid max-w-5xl gap-8 lg:grid-cols-[minmax(0,0.9fr)_minmax(440px,1fr)] lg:items-center">
        <div class="space-y-6">
          <div class="inline-flex items-center gap-2 rounded-full border border-sky-200 bg-white/80 px-4 py-2 text-xs font-semibold uppercase tracking-[0.32em] text-sky-800 shadow-sm backdrop-blur">
            OpenDrive
          </div>
          <div class="space-y-4">
            <h1 class="max-w-md text-3xl font-black tracking-tight text-slate-950 sm:text-5xl">
              {gettext("Create your workspace with clarity from the first access.")}
            </h1>
            <p class="max-w-xl text-sm leading-6 text-slate-600 sm:text-lg sm:leading-7">
              {gettext(
                "Centralize files, organize teams, and enter the right environment without washed-out screens or weak contrast."
              )}
            </p>
          </div>
          <div class="grid gap-3 sm:grid-cols-2">
            <div class="rounded-3xl border border-white/80 bg-white/75 p-4 shadow-sm backdrop-blur">
              <p class="text-sm font-semibold text-slate-900">{gettext("Higher contrast")}</p>
              <p class="mt-1 text-sm text-slate-600">
                {gettext("Fields, labels, and actions with immediate readability.")}
              </p>
            </div>
            <div class="rounded-3xl border border-white/80 bg-white/75 p-4 shadow-sm backdrop-blur">
              <p class="text-sm font-semibold text-slate-900">{gettext("Direct flow")}</p>
              <p class="mt-1 text-sm text-slate-600">
                {gettext("Account and workspace created in the same step.")}
              </p>
            </div>
          </div>
        </div>

        <.form
          for={@form}
          id="registration_form"
          phx-submit="save"
          phx-change="validate"
          class="space-y-6 rounded-[2rem] border border-white/90 bg-white px-5 py-6 shadow-[0_24px_80px_rgba(15,23,42,0.12)] ring-1 ring-slate-200/80 sm:px-8 sm:py-8"
        >
          <div class="space-y-3">
            <p class="text-sm font-semibold uppercase tracking-[0.28em] text-slate-500">
              {gettext("Create workspace")}
            </p>
            <div class="space-y-1">
              <h2 class="text-2xl font-bold tracking-tight text-slate-950">{gettext("Start now")}</h2>
              <p class="text-sm text-slate-600">
                {gettext("Already have an account?")}
                <.link
                  navigate={~p"/users/log-in"}
                  class="font-semibold text-sky-700 hover:text-sky-900 hover:underline"
                >
                  {gettext("Log in")}
                </.link>
              </p>
            </div>
          </div>

          <.input
            field={@form[:tenant_name]}
            type="text"
            label={gettext("Workspace name")}
            placeholder={gettext("Example: Operations")}
            required
          />
          <.input
            field={@form[:email]}
            type="email"
            label={gettext("Email")}
            placeholder={gettext("you@company.com")}
            autocomplete="username"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label={gettext("Password")}
            placeholder={gettext("Choose a secure password")}
            autocomplete="new-password"
            required
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label={gettext("Confirm password")}
            placeholder={gettext("Repeat your password")}
            autocomplete="new-password"
            required
          />

          <.button
            phx-disable-with={gettext("Creating...")}
            class="inline-flex h-12 w-full items-center justify-center rounded-2xl bg-slate-950 text-sm font-semibold text-white shadow-[0_18px_40px_rgba(15,23,42,0.22)] transition hover:-translate-y-0.5 hover:bg-slate-800"
          >
            {gettext("Create account and workspace")}
          </.button>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset =
      Accounts.change_user_registration_with_tenant(%User{}, %{}, validate_unique: false)

    {:ok, assign_form(socket, changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user_with_tenant(user_params, %{name: user_params["tenant_name"]}) do
      {:ok, %{user: user}} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Workspace created successfully."))
         |> push_navigate(to: ~p"/users/log-in", replace: true)
         |> then(fn socket -> assign(socket, :registered_user, user) end)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      Accounts.change_user_registration_with_tenant(%User{}, user_params, validate_unique: false)

    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
