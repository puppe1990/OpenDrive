defmodule OpenDriveWeb.UserAuth do
  use OpenDriveWeb, :verified_routes
  use Gettext, backend: OpenDriveWeb.Gettext

  import Phoenix.Controller
  import Plug.Conn

  alias OpenDrive.Accounts
  alias OpenDrive.Accounts.Scope

  @max_cookie_age_in_days 14
  @remember_me_cookie "_open_drive_web_user_remember_me"
  @remember_me_options [
    sign: true,
    max_age: @max_cookie_age_in_days * 24 * 60 * 60,
    same_site: "Lax"
  ]
  @session_reissue_age_in_days 7

  def log_in_user(conn, user, params \\ %{}) do
    user_return_to = get_session(conn, :user_return_to)
    scope = Accounts.build_scope(user)

    conn
    |> create_or_extend_session(user, scope, params)
    |> redirect(to: user_return_to || signed_in_path_for_scope(scope))
  end

  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      OpenDriveWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session(nil)
    |> delete_resp_cookie(@remember_me_cookie, @remember_me_options)
    |> redirect(to: ~p"/")
  end

  def fetch_current_scope_for_user(conn, _opts) do
    with {token, conn} <- ensure_user_token(conn),
         {user, token_inserted_at} <- Accounts.get_user_by_session_token(token) do
      scope = Accounts.build_scope(user, get_session(conn, :current_tenant_id))

      conn
      |> assign(:current_scope, scope)
      |> maybe_reissue_user_session_token(user, scope, token_inserted_at)
    else
      nil -> assign(conn, :current_scope, nil)
    end
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, conn |> put_token_in_session(token) |> put_session(:user_remember_me, true)}
      else
        nil
      end
    end
  end

  defp maybe_reissue_user_session_token(conn, user, scope, token_inserted_at) do
    token_age = DateTime.diff(DateTime.utc_now(:second), token_inserted_at, :day)

    if token_age >= @session_reissue_age_in_days do
      create_or_extend_session(conn, user, scope, %{})
    else
      conn
    end
  end

  defp create_or_extend_session(conn, user, scope, params) do
    token = Accounts.generate_user_session_token(user)
    remember_me = get_session(conn, :user_remember_me)

    conn
    |> renew_session(user)
    |> put_token_in_session(token)
    |> put_session(:current_tenant_id, scope && Scope.tenant_id(scope))
    |> maybe_write_remember_me_cookie(token, params, remember_me)
  end

  defp renew_session(
         %Plug.Conn{assigns: %{current_scope: %Scope{user: %{id: user_id}}}} = conn,
         %{id: user_id}
       ),
       do: conn

  defp renew_session(conn, _user) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}, _),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, token, _params, true),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, _token, _params, _), do: conn

  defp write_remember_me_cookie(conn, token) do
    conn
    |> put_session(:user_remember_me, true)
    |> put_resp_cookie(@remember_me_cookie, token, @remember_me_options)
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, user_session_topic(token))
  end

  def disconnect_sessions(tokens) do
    Enum.each(tokens, fn %{token: token} ->
      OpenDriveWeb.Endpoint.broadcast(user_session_topic(token), "disconnect", %{})
    end)
  end

  defp user_session_topic(token), do: "users_sessions:#{Base.url_encode64(token)}"

  def on_mount(:mount_current_scope, _params, session, socket) do
    {:cont, mount_current_scope(socket, session)}
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if Scope.authenticated?(socket.assigns.current_scope) do
      {:cont, socket}
    else
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(:error, gettext("You must log in to access this page."))
       |> Phoenix.LiveView.redirect(to: ~p"/users/log-in")}
    end
  end

  def on_mount(:require_sudo_mode, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if Accounts.sudo_mode?(socket.assigns.current_scope.user, -10) do
      {:cont, socket}
    else
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(
         :error,
         gettext("You must re-authenticate to access this page.")
       )
       |> Phoenix.LiveView.redirect(to: ~p"/users/log-in")}
    end
  end

  defp mount_current_scope(socket, session) do
    Phoenix.Component.assign_new(socket, :current_scope, fn ->
      {user, _} =
        if user_token = session["user_token"] do
          Accounts.get_user_by_session_token(user_token)
        end || {nil, nil}

      Accounts.build_scope(user, session["current_tenant_id"])
    end)
  end

  def signed_in_path(%Plug.Conn{assigns: %{current_scope: %Scope{user: %Accounts.User{}}}}),
    do: ~p"/app"

  def signed_in_path(%Phoenix.LiveView.Socket{}), do: ~p"/app"
  def signed_in_path(_), do: ~p"/"
  defp signed_in_path_for_scope(%Scope{user: %Accounts.User{}}), do: ~p"/app"
  defp signed_in_path_for_scope(_), do: ~p"/"

  def require_authenticated_user(conn, _opts) do
    if Scope.authenticated?(conn.assigns.current_scope) do
      conn
    else
      conn
      |> put_flash(:error, gettext("You must log in to access this page."))
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log-in")
      |> halt()
    end
  end

  defp maybe_store_return_to(%{method: "GET"} = conn),
    do: put_session(conn, :user_return_to, current_path(conn))

  defp maybe_store_return_to(conn), do: conn
end
