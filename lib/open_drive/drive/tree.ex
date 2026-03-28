defmodule OpenDrive.Drive.Tree do
  @moduledoc false

  import Ecto.Query, warn: false

  alias OpenDrive.Accounts.Scope
  alias OpenDrive.Drive.{File, Folder}
  alias OpenDrive.Repo

  def subtree_folder_ids(%Scope{} = scope, root_folder_id) do
    do_subtree_folder_ids(scope, MapSet.new([root_folder_id]), [root_folder_id])
    |> MapSet.to_list()
  end

  def deleted_root_folder_ids(%Scope{} = scope) do
    tenant_id = Scope.tenant_id(scope)

    Folder
    |> where([f], f.tenant_id == ^tenant_id and not is_nil(f.deleted_at))
    |> select([f], f.id)
    |> Repo.all()
  end

  def files_in_folder_ids(%Scope{} = scope, folder_ids, opts \\ []) do
    if folder_ids == [] do
      []
    else
      tenant_id = Scope.tenant_id(scope)
      include_deleted_only? = Keyword.get(opts, :deleted_only, false)

      File
      |> where([f], f.tenant_id == ^tenant_id and f.folder_id in ^folder_ids)
      |> maybe_deleted_only(include_deleted_only?)
      |> preload(:file_object)
      |> Repo.all()
    end
  end

  defp do_subtree_folder_ids(_scope, seen, []), do: seen

  defp do_subtree_folder_ids(%Scope{} = scope, seen, frontier) do
    tenant_id = Scope.tenant_id(scope)

    children_ids =
      Folder
      |> where([f], f.tenant_id == ^tenant_id and f.parent_folder_id in ^frontier)
      |> select([f], f.id)
      |> Repo.all()
      |> Enum.reject(&MapSet.member?(seen, &1))

    do_subtree_folder_ids(
      scope,
      Enum.reduce(children_ids, seen, &MapSet.put(&2, &1)),
      children_ids
    )
  end

  defp maybe_deleted_only(query, true), do: where(query, [f], not is_nil(f.deleted_at))
  defp maybe_deleted_only(query, false), do: query
end
