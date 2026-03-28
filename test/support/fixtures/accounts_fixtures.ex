defmodule OpenDrive.AccountsFixtures do
  @moduledoc false

  import Ecto.Query

  alias OpenDrive.Accounts
  alias OpenDrive.Tenancy

  def unique_user_email, do: "user#{System.unique_integer([:positive])}@example.com"
  def valid_user_password, do: "super secure 123"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password(),
      password_confirmation: valid_user_password()
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  def workspace_fixture(attrs \\ %{}) do
    user = Map.get(attrs, :user) || user_fixture()
    tenant_name = Map.get(attrs, :tenant_name, "Workspace #{System.unique_integer([:positive])}")

    {:ok, tenant} = Tenancy.create_tenant_with_owner(user, %{name: tenant_name})
    scope = Accounts.build_scope(user, tenant.id)

    %{user: user, tenant: tenant, scope: scope}
  end

  def membership_fixture(workspace, attrs \\ %{}) do
    user = Map.get(attrs, :user) || user_fixture()
    role = Map.get(attrs, :role, "member")

    {:ok, membership} =
      Tenancy.add_member(workspace.scope, workspace.tenant, %{email: user.email, role: role})

    %{user: user, membership: membership, scope: Accounts.build_scope(user, workspace.tenant.id)}
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    OpenDrive.Repo.update_all(
      from(t in OpenDrive.Accounts.UserToken, where: t.token == ^token),
      set: [authenticated_at: authenticated_at]
    )
  end
end
