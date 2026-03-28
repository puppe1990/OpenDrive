defmodule OpenDrive.Audit.AuditEvent do
  use Ecto.Schema
  import Ecto.Changeset

  alias OpenDrive.Accounts.User
  alias OpenDrive.Tenancy.Tenant

  schema "audit_events" do
    field :action, :string
    field :resource_type, :string
    field :resource_id, :integer
    field :metadata, :map, default: %{}

    belongs_to :tenant, Tenant
    belongs_to :actor_user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(audit_event, attrs) do
    audit_event
    |> cast(attrs, [:tenant_id, :actor_user_id, :action, :resource_type, :resource_id, :metadata])
    |> validate_required([:tenant_id, :action, :resource_type, :resource_id])
  end
end
