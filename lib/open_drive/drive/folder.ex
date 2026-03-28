defmodule OpenDrive.Drive.Folder do
  use Ecto.Schema
  import Ecto.Changeset

  alias OpenDrive.Accounts.User
  alias OpenDrive.Tenancy.Tenant

  schema "folders" do
    field :name, :string
    field :deleted_at, :utc_datetime

    belongs_to :tenant, Tenant
    belongs_to :parent_folder, __MODULE__
    belongs_to :created_by_user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(folder, attrs) do
    folder
    |> cast(attrs, [:tenant_id, :parent_folder_id, :created_by_user_id, :name, :deleted_at])
    |> validate_required([:tenant_id, :name])
    |> validate_length(:name, min: 1, max: 120)
    |> unique_constraint(:name, name: :folders_active_name_unique)
  end
end
