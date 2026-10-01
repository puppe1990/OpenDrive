defmodule OpenDriveWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use OpenDriveWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :locale, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div
      {@rest}
      class="od-app-shell min-h-screen text-slate-950"
    >
      <header class="border-b border-slate-200/80 bg-white/80 backdrop-blur-xl">
        <div class="mx-auto flex max-w-[1440px] flex-col gap-3 px-4 py-3 sm:px-6 lg:flex-row lg:items-center lg:gap-8 lg:px-8">
          <a href="/" class="flex items-center gap-3">
            <div class="od-brand-mark size-10 rounded-[0.9rem]" aria-hidden="true"></div>
            <div>
              <p class="text-lg font-bold tracking-[-0.04em] text-slate-950">
                OpenDrive
              </p>
              <p class="text-[10px] font-semibold uppercase tracking-[0.22em] text-slate-400">
                Work files
              </p>
            </div>
          </a>

          <%= if @current_scope && @current_scope.user do %>
            <div class="hidden lg:flex lg:flex-1 lg:justify-center">
              <div class="flex items-center gap-1 rounded-xl bg-slate-100/80 p-1">
                <.link
                  navigate={~p"/app"}
                  class="inline-flex h-9 items-center justify-center rounded-lg px-4 text-sm font-semibold text-slate-600 transition hover:bg-white hover:text-slate-950 hover:shadow-sm"
                >
                  {gettext("Drive")}
                </.link>
                <.link
                  navigate={~p"/app/members"}
                  class="inline-flex h-9 items-center justify-center rounded-lg px-4 text-sm font-semibold text-slate-600 transition hover:bg-white hover:text-slate-950 hover:shadow-sm"
                >
                  {gettext("Members")}
                </.link>
                <.link
                  navigate={~p"/app/trash"}
                  class="inline-flex h-9 items-center justify-center rounded-lg px-4 text-sm font-semibold text-slate-600 transition hover:bg-white hover:text-slate-950 hover:shadow-sm"
                >
                  {gettext("Trash")}
                </.link>
                <.link
                  href={~p"/users/settings"}
                  class="inline-flex h-9 items-center justify-center rounded-lg px-4 text-sm font-semibold text-slate-600 transition hover:bg-white hover:text-slate-950 hover:shadow-sm"
                >
                  {gettext("Settings")}
                </.link>
              </div>
            </div>
          <% end %>

          <div class="flex flex-col gap-3 lg:ml-auto lg:items-end">
            <%= if @current_scope && @current_scope.user do %>
              <div class="lg:hidden">
                <.tenant_switcher current_scope={@current_scope} />
                <div class="flex items-center gap-1 overflow-x-auto rounded-xl bg-slate-100 p-1">
                  <.link
                    navigate={~p"/app"}
                    class="inline-flex h-9 flex-1 items-center justify-center rounded-lg px-3 text-sm font-semibold text-slate-700 transition hover:bg-white hover:text-slate-950"
                  >
                    {gettext("Drive")}
                  </.link>
                  <.link
                    navigate={~p"/app/members"}
                    class="inline-flex h-9 flex-1 items-center justify-center rounded-lg px-3 text-sm font-semibold text-slate-700 transition hover:bg-white hover:text-slate-950"
                  >
                    {gettext("Members")}
                  </.link>
                  <.link
                    navigate={~p"/app/trash"}
                    class="inline-flex h-9 flex-1 items-center justify-center rounded-lg px-3 text-sm font-semibold text-slate-700 transition hover:bg-white hover:text-slate-950"
                  >
                    {gettext("Trash")}
                  </.link>
                  <.link
                    href={~p"/users/settings"}
                    class="inline-flex h-9 flex-1 items-center justify-center rounded-lg px-3 text-sm font-semibold text-slate-700 transition hover:bg-white hover:text-slate-950"
                  >
                    {gettext("Settings")}
                  </.link>
                </div>
              </div>

              <div class="flex flex-wrap items-center gap-2 lg:justify-end">
                <.tenant_switcher current_scope={@current_scope} />
                <.translation_switcher locale={@locale || Gettext.get_locale(OpenDriveWeb.Gettext)} />
                <.link
                  href={~p"/users/log-out"}
                  method="delete"
                  class="inline-flex h-10 flex-1 items-center justify-center rounded-xl border border-slate-300 bg-white px-4 text-sm font-semibold text-slate-700 transition hover:border-slate-400 hover:text-slate-950 sm:flex-none"
                >
                  {gettext("Log out")}
                </.link>
              </div>
            <% else %>
              <div class="flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-center lg:justify-end">
                <.translation_switcher locale={@locale || Gettext.get_locale(OpenDriveWeb.Gettext)} />
                <.link
                  navigate={~p"/users/log-in"}
                  class="inline-flex h-11 items-center justify-center rounded-2xl px-4 text-sm font-semibold text-slate-700 transition hover:bg-white/80 hover:text-slate-950"
                >
                  {gettext("Log in")}
                </.link>
                <.link
                  navigate={~p"/users/register"}
                  class="inline-flex h-11 items-center justify-center rounded-2xl bg-slate-950 px-5 text-sm font-semibold text-white shadow-[0_14px_30px_rgba(15,23,42,0.18)] transition hover:-translate-y-0.5 hover:bg-slate-800"
                >
                  {gettext("Create workspace")}
                </.link>
              </div>
            <% end %>
          </div>
        </div>
      </header>

      <main class="px-4 pb-16 pt-8 sm:px-6 lg:px-8">
        <div class="mx-auto max-w-[1440px] space-y-4">
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :locale, :string, required: true

  def translation_switcher(assigns) do
    ~H"""
    <div class="inline-flex rounded-xl bg-slate-100 p-1 shadow-[inset_0_1px_0_rgba(255,255,255,0.8)] ring-1 ring-slate-200/80">
      <.link
        href="?locale=pt-BR"
        class={[
          "rounded-lg px-3 py-2 text-sm font-semibold tracking-[-0.02em] transition",
          @locale == "pt_BR" && "bg-white text-slate-950 shadow-[0_6px_16px_rgba(15,23,42,0.12)]",
          @locale != "pt_BR" && "text-slate-500 hover:text-slate-800"
        ]}
      >
        PT-BR
      </.link>
      <.link
        href="?locale=en"
        class={[
          "rounded-lg px-3 py-2 text-sm font-semibold tracking-[-0.02em] transition",
          @locale == "en" && "bg-white text-slate-950 shadow-[0_6px_16px_rgba(15,23,42,0.12)]",
          @locale != "en" && "text-slate-500 hover:text-slate-800"
        ]}
      >
        EN
      </.link>
    </div>
    """
  end

  attr :current_scope, :map, required: true

  def tenant_switcher(assigns) do
    ~H"""
    <form
      :if={Enum.count(@current_scope.memberships) > 1}
      action={~p"/app/switch-tenant"}
      method="post"
      class="w-full sm:w-auto"
    >
      <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
      <select
        name="tenant_id"
        class="select select-bordered select-sm w-full sm:w-auto"
        onchange="this.form.submit()"
      >
        <%= for membership <- @current_scope.memberships do %>
          <option
            value={membership.tenant_id}
            selected={membership.tenant_id == @current_scope.tenant.id}
          >
            {membership.tenant.name}
          </option>
        <% end %>
      </select>
    </form>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
