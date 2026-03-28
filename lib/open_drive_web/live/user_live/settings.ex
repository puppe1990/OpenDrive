defmodule OpenDriveWeb.UserLive.Settings do
  use OpenDriveWeb, :live_view

  alias OpenDrive.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="grid gap-8 xl:grid-cols-[minmax(0,1.4fr)_minmax(320px,0.8fr)]">
        <div class="space-y-6">
          <div class="relative overflow-hidden rounded-[2rem] border border-white/70 bg-white/90 p-6 shadow-[0_30px_90px_rgba(15,23,42,0.12)] ring-1 ring-slate-200/70 backdrop-blur sm:p-8">
            <div class="pointer-events-none absolute inset-x-0 top-0 h-28 bg-[linear-gradient(135deg,rgba(14,165,233,0.12),rgba(255,255,255,0))]" />
            <div class="relative space-y-5">
              <div class="flex flex-wrap items-start justify-between gap-4">
                <div class="space-y-3">
                  <span class="inline-flex items-center rounded-full border border-sky-200 bg-sky-50 px-3 py-1 text-[0.7rem] font-semibold uppercase tracking-[0.32em] text-sky-800">
                    {gettext("Account Settings")}
                  </span>
                  <div class="space-y-2">
                    <h1 class="max-w-2xl text-3xl font-black tracking-tight text-slate-950 sm:text-4xl">
                      {gettext("Adjust your access without losing workspace context.")}
                    </h1>
                    <p class="max-w-2xl text-sm leading-7 text-slate-600 sm:text-base">
                      {gettext(
                        "Update your email and password in a clearer panel focused on what changes your account security."
                      )}
                    </p>
                  </div>
                </div>

                <div class="rounded-3xl border border-slate-200 bg-slate-950 px-4 py-4 text-white shadow-[0_18px_50px_rgba(15,23,42,0.22)]">
                  <p class="text-[0.68rem] font-semibold uppercase tracking-[0.28em] text-slate-300">
                    {gettext("Current login")}
                  </p>
                  <p class="mt-2 text-sm font-semibold">{@current_email}</p>
                  <p class="mt-1 text-xs leading-5 text-slate-300">
                    {gettext("Use this panel to manage your account credentials.")}
                  </p>
                </div>
              </div>

              <div class="grid gap-4 sm:grid-cols-3">
                <div class="rounded-3xl border border-slate-200 bg-slate-50/90 p-4">
                  <p class="text-[0.68rem] font-semibold uppercase tracking-[0.28em] text-slate-500">
                    {gettext("Current email")}
                  </p>
                  <p class="mt-2 break-all text-sm font-semibold text-slate-900">{@current_email}</p>
                </div>
                <div class="rounded-3xl border border-slate-200 bg-slate-50/90 p-4">
                  <p class="text-[0.68rem] font-semibold uppercase tracking-[0.28em] text-slate-500">
                    {gettext("Re-authentication")}
                  </p>
                  <p class="mt-2 text-sm font-semibold text-slate-900">
                    {gettext("Required only for sensitive changes")}
                  </p>
                </div>
                <div class="rounded-3xl border border-slate-200 bg-slate-50/90 p-4">
                  <p class="text-[0.68rem] font-semibold uppercase tracking-[0.28em] text-slate-500">
                    {gettext("Scope")}
                  </p>
                  <p class="mt-2 text-sm font-semibold text-slate-900">
                    {gettext("Personal account linked to the workspace")}
                  </p>
                </div>
              </div>
            </div>
          </div>

          <div class="grid gap-6">
            <section class="rounded-[2rem] border border-white/80 bg-white/95 p-6 shadow-[0_24px_80px_rgba(15,23,42,0.10)] ring-1 ring-slate-200/70 backdrop-blur sm:p-8">
              <div class="mb-6 flex items-start justify-between gap-4">
                <div>
                  <p class="text-[0.72rem] font-semibold uppercase tracking-[0.3em] text-slate-500">
                    {gettext("Email")}
                  </p>
                  <h2 class="mt-2 text-2xl font-bold tracking-tight text-slate-950">
                    {gettext("Change primary address")}
                  </h2>
                  <p class="mt-2 max-w-2xl text-sm leading-6 text-slate-600">
                    {gettext(
                      "The new address will receive a confirmation link before the change takes effect."
                    )}
                  </p>
                </div>
                <div class="hidden rounded-2xl border border-sky-200 bg-sky-50 px-3 py-2 text-xs font-semibold text-sky-800 sm:block">
                  {gettext("Change confirmed by email")}
                </div>
              </div>

              <.form
                for={@email_form}
                id="email_form"
                phx-submit="update_email"
                phx-change="validate_email"
                class="space-y-5"
              >
                <.input
                  field={@email_form[:email]}
                  type="email"
                  label={gettext("New email")}
                  autocomplete="username"
                  spellcheck="false"
                  required
                />
                <div class="flex flex-col gap-3 border-t border-slate-200 pt-5 sm:flex-row sm:items-center sm:justify-between">
                  <p class="text-sm leading-6 text-slate-500">
                    {gettext("Only change it if you also have access to the new inbox.")}
                  </p>
                  <.button
                    variant="primary"
                    phx-disable-with={gettext("Changing...")}
                    class="inline-flex h-12 items-center justify-center rounded-2xl bg-slate-950 px-6 text-sm font-semibold text-white shadow-[0_18px_40px_rgba(15,23,42,0.22)] transition hover:-translate-y-0.5 hover:bg-slate-800"
                  >
                    {gettext("Change Email")}
                  </.button>
                </div>
              </.form>
            </section>

            <section class="rounded-[2rem] border border-white/80 bg-white/95 p-6 shadow-[0_24px_80px_rgba(15,23,42,0.10)] ring-1 ring-slate-200/70 backdrop-blur sm:p-8">
              <div class="mb-6 flex items-start justify-between gap-4">
                <div>
                  <p class="text-[0.72rem] font-semibold uppercase tracking-[0.3em] text-slate-500">
                    {gettext("Password")}
                  </p>
                  <h2 class="mt-2 text-2xl font-bold tracking-tight text-slate-950">
                    {gettext("Set a new password")}
                  </h2>
                  <p class="mt-2 max-w-2xl text-sm leading-6 text-slate-600">
                    {gettext(
                      "When you save, old sessions are invalidated to reduce risk on devices that are already signed in."
                    )}
                  </p>
                </div>
                <div class="hidden rounded-2xl border border-amber-200 bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800 sm:block">
                  {gettext("Sensitive update")}
                </div>
              </div>

              <.form
                for={@password_form}
                id="password_form"
                action={~p"/users/update-password"}
                method="post"
                phx-change="validate_password"
                phx-submit="update_password"
                phx-trigger-action={@trigger_submit}
                class="space-y-5"
              >
                <input
                  name={@password_form[:email].name}
                  type="hidden"
                  id="hidden_user_email"
                  spellcheck="false"
                  value={@current_email}
                />
                <div class="grid gap-4 lg:grid-cols-2">
                  <.input
                    field={@password_form[:password]}
                    type="password"
                    label={gettext("New password")}
                    autocomplete="new-password"
                    spellcheck="false"
                    required
                  />
                  <.input
                    field={@password_form[:password_confirmation]}
                    type="password"
                    label={gettext("Confirm new password")}
                    autocomplete="new-password"
                    spellcheck="false"
                  />
                </div>
                <div class="flex flex-col gap-3 border-t border-slate-200 pt-5 sm:flex-row sm:items-center sm:justify-between">
                  <p class="text-sm leading-6 text-slate-500">
                    {gettext("Prefer a long, unique password that is not reused in other services.")}
                  </p>
                  <.button
                    variant="primary"
                    phx-disable-with={gettext("Saving...")}
                    class="inline-flex h-12 items-center justify-center rounded-2xl bg-slate-950 px-6 text-sm font-semibold text-white shadow-[0_18px_40px_rgba(15,23,42,0.22)] transition hover:-translate-y-0.5 hover:bg-slate-800"
                  >
                    {gettext("Save Password")}
                  </.button>
                </div>
              </.form>
            </section>
          </div>
        </div>

        <aside class="space-y-6">
          <section class="rounded-[2rem] border border-slate-200/80 bg-slate-950 p-6 text-white shadow-[0_24px_80px_rgba(15,23,42,0.18)] sm:p-7">
            <p class="text-[0.72rem] font-semibold uppercase tracking-[0.3em] text-slate-400">
              {gettext("Security Notes")}
            </p>
            <h2 class="mt-3 text-2xl font-bold tracking-tight">
              {gettext("Critical changes remain protected.")}
            </h2>
            <p class="mt-3 text-sm leading-6 text-slate-300">
              {gettext(
                "You can open this area at any time, but email and password changes require recent authentication to prevent improper changes."
              )}
            </p>

            <div class="mt-6 space-y-3">
              <div class="rounded-3xl border border-white/10 bg-white/5 p-4">
                <p class="text-sm font-semibold">{gettext("Old sessions are terminated")}</p>
                <p class="mt-1 text-sm leading-6 text-slate-300">
                  {gettext("When you change your password, previous tokens stop working.")}
                </p>
              </div>
              <div class="rounded-3xl border border-white/10 bg-white/5 p-4">
                <p class="text-sm font-semibold">{gettext("Email requires confirmation")}</p>
                <p class="mt-1 text-sm leading-6 text-slate-300">
                  {gettext(
                    "The account only points to the new address after the link in the email is clicked."
                  )}
                </p>
              </div>
            </div>
          </section>

          <section class="rounded-[2rem] border border-white/80 bg-white/95 p-6 shadow-[0_24px_80px_rgba(15,23,42,0.10)] ring-1 ring-slate-200/70 sm:p-7">
            <p class="text-[0.72rem] font-semibold uppercase tracking-[0.3em] text-slate-500">
              {gettext("Best practices")}
            </p>
            <ul class="mt-4 space-y-4 text-sm leading-6 text-slate-600">
              <li class="flex gap-3">
                <span class="mt-1 size-2 rounded-full bg-sky-500" />
                {gettext(
                  "Review your email before saving to avoid locking yourself out of the workspace."
                )}
              </li>
              <li class="flex gap-3">
                <span class="mt-1 size-2 rounded-full bg-sky-500" />
                {gettext("Use a password manager to generate long, unique combinations.")}
              </li>
              <li class="flex gap-3">
                <span class="mt-1 size-2 rounded-full bg-sky-500" />
                {gettext(
                  "If you are asked to re-authenticate, that is expected for sensitive changes."
                )}
              </li>
            </ul>
          </section>
        </aside>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, gettext("Email changed successfully."))

        {:error, _} ->
          put_flash(socket, :error, gettext("Email change link is invalid or it has expired."))
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user

    with :ok <- ensure_sudo_mode(user) do
      case Accounts.change_user_email(user, user_params) do
        %{valid?: true} = changeset ->
          Accounts.deliver_user_update_email_instructions(
            Ecto.Changeset.apply_action!(changeset, :insert),
            user.email,
            &url(~p"/users/settings/confirm-email/#{&1}")
          )

          info = gettext("A link to confirm your email change has been sent to the new address.")
          {:noreply, socket |> put_flash(:info, info)}

        changeset ->
          {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
      end
    else
      {:error, message} ->
        {:noreply, socket |> put_flash(:error, message) |> redirect(to: ~p"/users/log-in")}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user

    with :ok <- ensure_sudo_mode(user) do
      case Accounts.change_user_password(user, user_params) do
        %{valid?: true} = changeset ->
          {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

        changeset ->
          {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
      end
    else
      {:error, message} ->
        {:noreply, socket |> put_flash(:error, message) |> redirect(to: ~p"/users/log-in")}
    end
  end

  defp ensure_sudo_mode(user) do
    if Accounts.sudo_mode?(user) do
      :ok
    else
      {:error, gettext("You must re-authenticate to update your account settings.")}
    end
  end
end
