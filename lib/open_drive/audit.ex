defmodule OpenDrive.Audit do
  @moduledoc """
  Minimal audit trail for tenant actions.
  """

  alias OpenDrive.Accounts.Scope
  alias OpenDrive.Audit.AuditEvent
  alias OpenDrive.Repo

  def log(%Scope{} = scope, action, resource_type, resource_id, metadata \\ %{}) do
    attrs = %{
      tenant_id: Scope.tenant_id(scope),
      actor_user_id: scope.user.id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      metadata: metadata
    }

    %AuditEvent{}
    |> AuditEvent.changeset(attrs)
    |> Repo.insert()
  end
end
