defmodule OpenDrive.Drive.FileObject do
  use Ecto.Schema
  import Ecto.Changeset

  alias OpenDrive.Accounts.User
  alias OpenDrive.Tenancy.Tenant

  schema "file_objects" do
    field :bucket, :string
    field :key, :string
    field :checksum, :string
    field :content_type, :string
    field :size, :integer

    belongs_to :tenant, Tenant
    belongs_to :uploaded_by_user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(file_object, attrs) do
    file_object
    |> cast(attrs, [
      :tenant_id,
      :bucket,
      :key,
      :checksum,
      :content_type,
      :size,
      :uploaded_by_user_id
    ])
    |> validate_required([:tenant_id, :bucket, :key, :content_type, :size])
    |> unique_constraint([:bucket, :key])
  end
end
