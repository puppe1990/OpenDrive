defmodule OpenDrive.Tenancy do
  @moduledoc """
  Multi-tenant workspace and membership management.
  """

  import Ecto.Query, warn: false

  alias OpenDrive.Accounts.Scope
  alias OpenDrive.Accounts.User
  alias OpenDrive.Audit
  alias OpenDrive.Repo
  alias OpenDrive.Tenancy.{Membership, Tenant}

  def build_scope(%User{} = user, tenant_id \\ nil) do
    memberships =
      Membership
      |> where([m], m.user_id == ^user.id)
      |> join(:inner, [m], t in assoc(m, :tenant))
      |> preload([_m, t], tenant: t)
      |> order_by([_m, t], asc: t.name)
      |> Repo.all()

    membership =
      Enum.find(memberships, &(tenant_id && &1.tenant_id == tenant_id)) ||
        List.first(memberships)

    Scope.for_user(user,
      tenant: membership && membership.tenant,
      membership: membership,
      memberships: memberships
    )
  end

  def list_tenants_for_user(%User{} = user) do
    build_scope(user).memberships |> Enum.map(& &1.tenant)
  end

  def create_tenant_with_owner(%User{} = user, attrs) do
    Repo.transaction(fn ->
      slug = attrs |> Map.get("name", Map.get(attrs, :name, "")) |> slugify()

      with {:ok, tenant} <-
             %Tenant{}
             |> Tenant.changeset(
               attrs
               |> Map.put(:slug, slug)
               |> Map.put(:owner_user_id, user.id)
             )
             |> Repo.insert(),
           {:ok, membership} <-
             %Membership{}
             |> Membership.changeset(%{tenant_id: tenant.id, user_id: user.id, role: "owner"})
             |> Repo.insert() do
        scope =
          Scope.for_user(user, tenant: tenant, membership: membership, memberships: [membership])

        Audit.log(scope, "tenant.created", "tenant", tenant.id, %{name: tenant.name})
        tenant
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> normalize_transaction_result()
  end

  def add_member(%Scope{} = actor_scope, %Tenant{} = tenant, attrs) do
    with :ok <- authorize_membership_management(actor_scope, tenant.id),
         %User{} = user <-
           Repo.get_by(User, email: Map.get(attrs, :email) || Map.get(attrs, "email")) do
      role = Map.get(attrs, :role) || Map.get(attrs, "role") || "member"

      %Membership{}
      |> Membership.changeset(%{tenant_id: tenant.id, user_id: user.id, role: role})
      |> Repo.insert()
      |> case do
        {:ok, membership} ->
          Audit.log(actor_scope, "membership.added", "membership", membership.id, %{
            email: user.email,
            role: role
          })

          {:ok, Repo.preload(membership, [:user, :tenant])}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      nil -> {:error, :user_not_found}
      {:error, _} = error -> error
    end
  end

  def list_members(%Scope{} = scope) do
    Membership
    |> where([m], m.tenant_id == ^Scope.tenant_id(scope))
    |> preload(:user)
    |> order_by([m], asc: m.role, asc: m.inserted_at)
    |> Repo.all()
  end

  def get_current_tenant(%Scope{tenant: tenant}), do: tenant

  def authorize_membership_management(%Scope{} = scope, tenant_id) do
    if Scope.manage_members?(scope) and Scope.tenant_id(scope) == tenant_id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  def slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "workspace"
      slug -> slug
    end
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, reason}), do: {:error, reason}
end
