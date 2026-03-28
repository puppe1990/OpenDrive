defmodule OpenDriveWeb.UserLive.Registration do
  use OpenDriveWeb, :live_view

  alias OpenDrive.Accounts
  alias OpenDrive.Accounts.User
  alias OpenDriveWeb.UserAuth

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="mx-auto grid max-w-5xl gap-10 lg:grid-cols-[minmax(0,0.9fr)_minmax(440px,1fr)] lg:items-center">
        <div class="space-y-6">
          <div class="inline-flex items-center gap-2 rounded-full border border-sky-200 bg-white/80 px-4 py-2 text-xs font-semibold uppercase tracking-[0.32em] text-sky-800 shadow-sm backdrop-blur">
            OpenDrive
          </div>
          <div class="space-y-4">
            <h1 class="max-w-md text-4xl font-black tracking-tight text-slate-950 sm:text-5xl">
              Crie seu workspace com clareza desde o primeiro acesso.
            </h1>
            <p class="max-w-xl text-base leading-7 text-slate-600 sm:text-lg">
              Centralize arquivos, organize equipes e entre no ambiente certo sem uma tela lavada ou com contraste fraco.
            </p>
          </div>
          <div class="grid gap-3 sm:grid-cols-2">
            <div class="rounded-3xl border border-white/80 bg-white/75 p-4 shadow-sm backdrop-blur">
              <p class="text-sm font-semibold text-slate-900">Mais contraste</p>
              <p class="mt-1 text-sm text-slate-600">Campos, labels e ações com leitura imediata.</p>
            </div>
            <div class="rounded-3xl border border-white/80 bg-white/75 p-4 shadow-sm backdrop-blur">
              <p class="text-sm font-semibold text-slate-900">Fluxo direto</p>
              <p class="mt-1 text-sm text-slate-600">Conta e workspace criados no mesmo passo.</p>
            </div>
          </div>
        </div>

        <.form
          for={@form}
          id="registration_form"
          phx-submit="save"
          phx-change="validate"
          class="space-y-6 rounded-[2rem] border border-white/90 bg-white px-6 py-7 shadow-[0_24px_80px_rgba(15,23,42,0.12)] ring-1 ring-slate-200/80 sm:px-8 sm:py-8"
        >
          <div class="space-y-3">
            <p class="text-sm font-semibold uppercase tracking-[0.28em] text-slate-500">
              Criar workspace
            </p>
            <div class="space-y-1">
              <h2 class="text-2xl font-bold tracking-tight text-slate-950">Comece agora</h2>
              <p class="text-sm text-slate-600">
                Já tem conta?
                <.link
                  navigate={~p"/users/log-in"}
                  class="font-semibold text-sky-700 hover:text-sky-900 hover:underline"
                >
                  Entrar
                </.link>
              </p>
            </div>
          </div>

          <.input
            field={@form[:tenant_name]}
            type="text"
            label="Nome do workspace"
            placeholder="Ex.: Operações"
            required
          />
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            placeholder="voce@empresa.com"
            autocomplete="username"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Senha"
            placeholder="Defina uma senha segura"
            autocomplete="new-password"
            required
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label="Confirmar senha"
            placeholder="Repita sua senha"
            autocomplete="new-password"
            required
          />

          <.button
            phx-disable-with="Criando..."
            class="inline-flex h-12 w-full items-center justify-center rounded-2xl bg-slate-950 text-sm font-semibold text-white shadow-[0_18px_40px_rgba(15,23,42,0.22)] transition hover:-translate-y-0.5 hover:bg-slate-800"
          >
            Criar conta e workspace
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
         |> put_flash(:info, "Workspace criado com sucesso.")
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
