defmodule OpenDriveWeb.TenantSessionController do
  use OpenDriveWeb, :controller

  alias OpenDrive.Accounts

  def update(conn, %{"tenant_id" => tenant_id}) do
    with {parsed_tenant_id, ""} <- Integer.parse(tenant_id),
         scope when not is_nil(scope) <-
           Accounts.build_scope(conn.assigns.current_scope.user, parsed_tenant_id),
         tenant when not is_nil(tenant) <- scope.tenant do
      conn
      |> put_session(:current_tenant_id, tenant.id)
      |> redirect(to: ~p"/app")
    else
      _ ->
        conn
        |> put_flash(:error, gettext("Workspace unavailable."))
        |> redirect(to: ~p"/app")
    end
  end
end
