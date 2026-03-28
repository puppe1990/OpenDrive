defmodule OpenDrive.Repo.Migrations.AddActiveDirectoryUniquenessIndexes do
  use Ecto.Migration

  def change do
    execute(
      """
      CREATE UNIQUE INDEX folders_active_name_unique
      ON folders (tenant_id, ifnull(parent_folder_id, 0), name)
      WHERE deleted_at IS NULL
      """,
      "DROP INDEX IF EXISTS folders_active_name_unique"
    )

    execute(
      """
      CREATE UNIQUE INDEX files_active_name_unique
      ON files (tenant_id, ifnull(folder_id, 0), name)
      WHERE deleted_at IS NULL
      """,
      "DROP INDEX IF EXISTS files_active_name_unique"
    )
  end
end
