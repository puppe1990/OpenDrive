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

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen bg-[radial-gradient(circle_at_top_left,_rgba(14,165,233,0.18),_transparent_30%),radial-gradient(circle_at_top_right,_rgba(59,130,246,0.12),_transparent_24%),linear-gradient(180deg,_#f7fbff_0%,_#edf4ff_48%,_#f8fbff_100%)] text-slate-950">
      <header class="mx-auto flex max-w-7xl items-center justify-between px-4 py-6 sm:px-6 lg:px-8">
        <a href="/" class="flex items-center gap-3">
          <div class="flex size-11 items-center justify-center rounded-2xl bg-slate-950 text-sm font-black text-white">
            OD
          </div>
          <div>
            <p class="text-sm font-semibold uppercase tracking-[0.35em] text-slate-700">OpenDrive</p>
            <p class="text-xs text-slate-500">Phoenix LiveView</p>
          </div>
        </a>

        <div class="flex items-center gap-3">
          <%= if @current_scope && @current_scope.user do %>
            <.tenant_switcher current_scope={@current_scope} />
            <.link navigate={~p"/app"} class="btn btn-ghost">Drive</.link>
            <.link navigate={~p"/app/members"} class="btn btn-ghost">Members</.link>
            <.link navigate={~p"/app/trash"} class="btn btn-ghost">Trash</.link>
            <.link href={~p"/users/settings"} class="btn btn-ghost">Settings</.link>
            <.link href={~p"/users/log-out"} method="delete" class="btn btn-outline">Log out</.link>
          <% else %>
            <.link
              navigate={~p"/users/log-in"}
              class="inline-flex h-11 items-center rounded-2xl px-4 text-sm font-semibold text-slate-700 transition hover:bg-white/80 hover:text-slate-950"
            >
              Log in
            </.link>
            <.link
              navigate={~p"/users/register"}
              class="inline-flex h-11 items-center rounded-2xl bg-slate-950 px-5 text-sm font-semibold text-white shadow-[0_14px_30px_rgba(15,23,42,0.18)] transition hover:-translate-y-0.5 hover:bg-slate-800"
            >
              Create workspace
            </.link>
          <% end %>
        </div>
      </header>

      <main class="px-4 pb-16 pt-6 sm:px-6 lg:px-8">
        <div class="mx-auto max-w-7xl space-y-4">
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :current_scope, :map, required: true

  def tenant_switcher(assigns) do
    ~H"""
    <form
      :if={Enum.count(@current_scope.memberships) > 1}
      action={~p"/app/switch-tenant"}
      method="post"
    >
      <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
      <select name="tenant_id" class="select select-bordered select-sm" onchange="this.form.submit()">
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
