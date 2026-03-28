defmodule OpenDrive.Repo.Migrations.ScopeTenantSlugUniquenessToOwner do
  use Ecto.Migration

  def up do
    alter table(:tenants) do
      add :owner_user_id, references(:users, on_delete: :delete_all)
    end

    execute("""
    UPDATE tenants
    SET owner_user_id = (
      SELECT user_id
      FROM memberships
      WHERE memberships.tenant_id = tenants.id
        AND memberships.role = 'owner'
      ORDER BY memberships.id
      LIMIT 1
    )
    """)

    execute("DELETE FROM tenants WHERE owner_user_id IS NULL")

    drop_if_exists index(:tenants, [:slug])
    create unique_index(:tenants, [:owner_user_id, :slug])
    create index(:tenants, [:owner_user_id])
  end

  def down do
    drop_if_exists index(:tenants, [:owner_user_id, :slug])
    drop_if_exists index(:tenants, [:owner_user_id])

    alter table(:tenants) do
      remove :owner_user_id
    end

    create unique_index(:tenants, [:slug])
  end
end
