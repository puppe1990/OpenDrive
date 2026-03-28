defmodule OpenDriveWeb.TenantSessionController do
  use OpenDriveWeb, :controller

  alias OpenDrive.Accounts

  def update(conn, %{"tenant_id" => tenant_id}) do
    scope = Accounts.build_scope(conn.assigns.current_scope.user, String.to_integer(tenant_id))

    if scope && scope.tenant do
      conn
      |> put_session(:current_tenant_id, scope.tenant.id)
      |> redirect(to: ~p"/app")
    else
      conn
      |> put_flash(:error, gettext("Workspace unavailable."))
      |> redirect(to: ~p"/app")
    end
  end
end
