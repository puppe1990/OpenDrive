defmodule OpenDrive.Drive.File do
  use Ecto.Schema
  import Ecto.Changeset

  alias OpenDrive.Accounts.User
  alias OpenDrive.Drive.FileObject
  alias OpenDrive.Tenancy.Tenant

  schema "files" do
    field :name, :string
    field :deleted_at, :utc_datetime

    belongs_to :tenant, Tenant
    belongs_to :folder, OpenDrive.Drive.Folder
    belongs_to :file_object, FileObject
    belongs_to :uploaded_by_user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(file, attrs) do
    file
    |> cast(attrs, [
      :tenant_id,
      :folder_id,
      :file_object_id,
      :uploaded_by_user_id,
      :name,
      :deleted_at
    ])
    |> validate_required([:tenant_id, :file_object_id, :name])
    |> validate_length(:name, min: 1, max: 120)
  end
end
