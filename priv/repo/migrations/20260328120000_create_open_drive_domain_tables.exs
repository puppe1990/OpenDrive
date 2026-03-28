defmodule OpenDrive.Repo.Migrations.CreateOpenDriveDomainTables do
  use Ecto.Migration

  def change do
    create table(:tenants) do
      add :name, :string, null: false
      add :slug, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tenants, [:slug])

    create table(:memberships) do
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :role, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:memberships, [:tenant_id, :user_id])
    create index(:memberships, [:user_id])

    create table(:folders) do
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false
      add :parent_folder_id, references(:folders, on_delete: :nilify_all)
      add :created_by_user_id, references(:users, on_delete: :nilify_all)
      add :name, :string, null: false
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:folders, [:tenant_id])
    create index(:folders, [:parent_folder_id])
    create index(:folders, [:tenant_id, :deleted_at])

    create table(:file_objects) do
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false
      add :bucket, :string, null: false
      add :key, :string, null: false
      add :checksum, :string
      add :content_type, :string, null: false
      add :size, :integer, null: false
      add :uploaded_by_user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:file_objects, [:bucket, :key])
    create index(:file_objects, [:tenant_id])

    create table(:files) do
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false
      add :folder_id, references(:folders, on_delete: :nilify_all)
      add :file_object_id, references(:file_objects, on_delete: :restrict), null: false
      add :uploaded_by_user_id, references(:users, on_delete: :nilify_all)
      add :name, :string, null: false
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:files, [:tenant_id])
    create index(:files, [:folder_id])
    create index(:files, [:tenant_id, :deleted_at])

    create table(:audit_events) do
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false
      add :actor_user_id, references(:users, on_delete: :nilify_all)
      add :action, :string, null: false
      add :resource_type, :string, null: false
      add :resource_id, :integer, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:audit_events, [:tenant_id, :inserted_at])
    create index(:audit_events, [:resource_type, :resource_id])
  end
end
