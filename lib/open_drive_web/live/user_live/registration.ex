defmodule OpenDriveWeb.UserLive.Registration do
  use OpenDriveWeb, :live_view

  alias OpenDrive.Accounts
  alias OpenDrive.Accounts.User
  alias OpenDriveWeb.UserAuth

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="mx-auto max-w-xl space-y-8">
        <div class="space-y-3 text-center">
          <p class="text-sm uppercase tracking-[0.35em] text-sky-700">OpenDrive</p>
          <.header>
            Crie seu workspace
            <:subtitle>
              Já tem conta?
              <.link navigate={~p"/users/log-in"} class="font-semibold text-sky-700 hover:underline">
                Entrar
              </.link>
            </:subtitle>
          </.header>
        </div>

        <.form
          for={@form}
          id="registration_form"
          phx-submit="save"
          phx-change="validate"
          class="space-y-5 rounded-3xl border border-slate-200 bg-white p-8 shadow-sm"
        >
          <.input field={@form[:tenant_name]} type="text" label="Nome do workspace" required />
          <.input field={@form[:email]} type="email" label="Email" autocomplete="username" required />
          <.input
            field={@form[:password]}
            type="password"
            label="Senha"
            autocomplete="new-password"
            required
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label="Confirmar senha"
            autocomplete="new-password"
            required
          />

          <.button phx-disable-with="Criando..." class="btn btn-primary w-full">
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
    changeset = Accounts.change_user_registration(%User{}, %{}, validate_unique: false)

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
    changeset = Accounts.change_user_registration(%User{}, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
