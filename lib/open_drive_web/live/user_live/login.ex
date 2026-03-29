defmodule OpenDriveWeb.UserLive.Login do
  use OpenDriveWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="mx-auto grid max-w-5xl gap-8 lg:grid-cols-[minmax(0,0.9fr)_minmax(420px,0.95fr)] lg:items-center">
        <div class="space-y-6">
          <div class="inline-flex items-center gap-2 rounded-full border border-sky-200 bg-white/80 px-4 py-2 text-xs font-semibold uppercase tracking-[0.32em] text-sky-800 shadow-sm backdrop-blur">
            OpenDrive
          </div>
          <div class="space-y-4">
            <h1 class="max-w-md text-3xl font-black tracking-tight text-slate-950 sm:text-5xl">
              {gettext("Enter your workspace without visual strain.")}
            </h1>
            <p class="max-w-xl text-sm leading-6 text-slate-600 sm:text-lg sm:leading-7">
              {gettext(
                "Direct access, legible fields, and a clear visual focus for people who just want to sign in and work."
              )}
            </p>
          </div>
        </div>

        <.form
          :let={f}
          for={@form}
          id="login_form"
          action={~p"/users/log-in"}
          class="space-y-6 rounded-[2rem] border border-white/90 bg-white px-5 py-6 shadow-[0_24px_80px_rgba(15,23,42,0.12)] ring-1 ring-slate-200/80 sm:px-8 sm:py-8"
        >
          <div class="space-y-3">
            <p class="text-sm font-semibold uppercase tracking-[0.28em] text-slate-500">
              {gettext("Log in")}
            </p>
            <div class="space-y-1">
              <h2 class="text-2xl font-bold tracking-tight text-slate-950">
                {gettext("Access your workspace")}
              </h2>
              <p class="text-sm text-slate-600">
                {gettext("Don't have an account yet?")}
                <.link
                  navigate={~p"/users/register"}
                  class="font-semibold text-sky-700 hover:text-sky-900 hover:underline"
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

          <.button class="inline-flex h-12 w-full items-center justify-center rounded-2xl bg-slate-950 text-sm font-semibold text-white shadow-[0_18px_40px_rgba(15,23,42,0.22)] transition hover:-translate-y-0.5 hover:bg-slate-800">
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
