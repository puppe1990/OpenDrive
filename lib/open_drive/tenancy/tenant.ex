defmodule OpenDrive.Tenancy.Tenant do
  use Ecto.Schema
  import Ecto.Changeset

  alias OpenDrive.Tenancy.Membership

  schema "tenants" do
    field :name, :string
    field :slug, :string

    has_many :memberships, Membership

    timestamps(type: :utc_datetime)
  end

  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [:name, :slug])
    |> validate_required([:name, :slug])
    |> validate_length(:name, min: 2, max: 80)
    |> validate_length(:slug, min: 2, max: 80)
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    |> unique_constraint(:slug)
  end
end
