defmodule OpenDriveWeb.UserLive.Login do
  use OpenDriveWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="flex min-h-[calc(100vh-12rem)] items-center justify-center py-8 sm:py-12">
        <.form
          :let={f}
          for={@form}
          id="login_form"
          action={~p"/users/log-in"}
          class="od-reveal w-full max-w-xl space-y-6 rounded-[2rem] border border-white/90 bg-white px-5 py-7 shadow-[0_24px_80px_rgba(15,23,42,0.12)] ring-1 ring-slate-200/80 sm:px-10 sm:py-10"
        >
          <div class="space-y-3 text-center">
            <div class="od-brand-mark mx-auto size-11 rounded-xl" aria-hidden="true"></div>
            <p class="pt-2 text-xs font-semibold uppercase tracking-[0.28em] text-blue-600">
              {gettext("Log in")}
            </p>
            <div class="space-y-1">
              <h1 class="text-3xl font-bold tracking-[-0.035em] text-slate-950">
                {gettext("Access your workspace")}
              </h1>
              <p class="pt-1 text-sm text-slate-600">
                {gettext("Don't have an account yet?")}
                <.link
                  navigate={~p"/users/register"}
                  class="font-semibold text-blue-600 hover:text-blue-800 hover:underline"
                >
                  {gettext("Create one now")}
                </.link>
              </p>
            </div>
          </div>

          <.input
            field={f[:email]}
            type="email"
            label={gettext("Email")}
            placeholder={gettext("you@company.com")}
            autocomplete="username"
            required
          />
          <.input
            field={f[:password]}
            type="password"
            label={gettext("Password")}
            placeholder={gettext("Your password")}
            autocomplete="current-password"
            required
          />

          <label class="flex items-center gap-3 text-sm font-medium text-slate-700">
            <input
              type="checkbox"
              name={f[:remember_me].name}
              value="true"
              class="checkbox checkbox-sm border-slate-400"
            /> {gettext("Keep me signed in")}
          </label>

          <.button
            type="submit"
            data-submit-loading
            loading_label={gettext("Logging in...")}
            class="inline-flex h-12 w-full items-center justify-center rounded-xl bg-blue-600 text-sm font-semibold text-white shadow-[0_16px_36px_rgba(37,99,235,0.24)] transition hover:-translate-y-0.5 hover:bg-blue-700"
          >
            {gettext("Log in")}
          </.button>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    {:ok, assign(socket, form: to_form(%{"email" => email}, as: "user"))}
  end
end
