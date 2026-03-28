defmodule OpenDrive.TenancyTest do
  use OpenDrive.DataCase

  alias OpenDrive.Accounts
  alias OpenDrive.Tenancy

  import OpenDrive.AccountsFixtures

  test "add_member/3 allows owner to add existing users" do
    workspace = workspace_fixture()
    invited = user_fixture()

    assert {:ok, membership} =
             Tenancy.add_member(workspace.scope, workspace.tenant, %{
               email: invited.email,
               role: "member"
             })

    assert membership.role == "member"
    assert Accounts.build_scope(invited, workspace.tenant.id).tenant.id == workspace.tenant.id
  end

  test "add_member/3 rejects member-managed invitations" do
    workspace = workspace_fixture()
    member_scope = membership_fixture(workspace).scope
    invited = user_fixture()

    assert {:error, :forbidden} =
             Tenancy.add_member(member_scope, workspace.tenant, %{
               email: invited.email,
               role: "member"
             })
  end

  test "build_scope/2 switches tenants for the same user" do
    owner = user_fixture()
    {:ok, tenant_a} = Tenancy.create_tenant_with_owner(owner, %{name: "A Team"})
    {:ok, tenant_b} = Tenancy.create_tenant_with_owner(owner, %{name: "B Team"})

    assert Accounts.build_scope(owner, tenant_a.id).tenant.id == tenant_a.id
    assert Accounts.build_scope(owner, tenant_b.id).tenant.id == tenant_b.id
  end
end
