defmodule OpenDrive.Tenancy.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  alias OpenDrive.Accounts.User
  alias OpenDrive.Tenancy.Tenant

  @roles ~w(owner admin member)

  schema "memberships" do
    field :role, :string

    belongs_to :tenant, Tenant
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:tenant_id, :user_id, :role])
    |> validate_required([:tenant_id, :user_id, :role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:tenant_id, :user_id])
  end

  def roles, do: @roles
end
