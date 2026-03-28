defmodule OpenDriveWeb.UserLive.Login do
  use OpenDriveWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="mx-auto max-w-lg space-y-8">
        <div class="space-y-3 text-center">
          <p class="text-sm uppercase tracking-[0.35em] text-sky-700">OpenDrive</p>
          <.header>
            Entrar no workspace
            <:subtitle>
              Ainda não tem conta?
              <.link navigate={~p"/users/register"} class="font-semibold text-sky-700 hover:underline">
                Criar agora
              </.link>
            </:subtitle>
          </.header>
        </div>

        <.form
          :let={f}
          for={@form}
          id="login_form"
          action={~p"/users/log-in"}
          class="space-y-5 rounded-3xl border border-slate-200 bg-white p-8 shadow-sm"
        >
          <.input field={f[:email]} type="email" label="Email" autocomplete="username" required />
          <.input
            field={f[:password]}
            type="password"
            label="Senha"
            autocomplete="current-password"
            required
          />

          <label class="flex items-center gap-3 text-sm text-slate-600">
            <input
              type="checkbox"
              name={f[:remember_me].name}
              value="true"
              class="checkbox checkbox-sm"
            /> Manter sessão ativa
          </label>

          <.button class="btn btn-primary w-full">
            Entrar
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
