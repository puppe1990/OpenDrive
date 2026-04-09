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

  test "add_member/3 rejects non-existent email" do
    workspace = workspace_fixture()

    assert {:error, :user_not_found} =
             Tenancy.add_member(workspace.scope, workspace.tenant, %{
               email: "nonexistent@example.com",
               role: "member"
             })
  end

  test "add_member/3 rejects invalid role" do
    workspace = workspace_fixture()
    invited = user_fixture()

    assert {:error, changeset} =
             Tenancy.add_member(workspace.scope, workspace.tenant, %{
               email: invited.email,
               role: "superadmin"
             })

    assert "is invalid" in errors_on(changeset).role
  end

  test "add_member/3 rejects adding same user twice" do
    workspace = workspace_fixture()
    invited = user_fixture()

    assert {:ok, _} =
             Tenancy.add_member(workspace.scope, workspace.tenant, %{
               email: invited.email,
               role: "member"
             })

    assert {:error, changeset} =
             Tenancy.add_member(workspace.scope, workspace.tenant, %{
               email: invited.email,
               role: "admin"
             })

    assert "has already been taken" in errors_on(changeset).tenant_id
  end

  test "list_members/2 returns all members for a tenant" do
    workspace = workspace_fixture()
    member1 = user_fixture()
    member2 = user_fixture()

    {:ok, _} =
      Tenancy.add_member(workspace.scope, workspace.tenant, %{
        email: member1.email,
        role: "member"
      })

    {:ok, _} =
      Tenancy.add_member(workspace.scope, workspace.tenant, %{
        email: member2.email,
        role: "admin"
      })

    members = Tenancy.list_members(workspace.scope)
    assert length(members) == 3
  end

  test "create_tenant_with_owner/2 rejects empty name" do
    owner = user_fixture()

    assert {:error, changeset} = Tenancy.create_tenant_with_owner(owner, %{name: ""})
    assert "can't be blank" in errors_on(changeset).name
  end

  test "create_tenant_with_owner/2 generates unique slug for different users" do
    owner1 = user_fixture()
    owner2 = user_fixture()

    {:ok, tenant1} = Tenancy.create_tenant_with_owner(owner1, %{name: "My Workspace"})
    {:ok, tenant2} = Tenancy.create_tenant_with_owner(owner2, %{name: "My Workspace"})

    assert tenant1.slug == tenant2.slug
    assert String.contains?(tenant1.slug, "my-workspace")
  end

  test "list_tenants_for_user/1 returns all tenants for a user" do
    owner = user_fixture()

    {:ok, _tenant1} = Tenancy.create_tenant_with_owner(owner, %{name: "Team A"})
    {:ok, _tenant2} = Tenancy.create_tenant_with_owner(owner, %{name: "Team B"})

    tenants = Tenancy.list_tenants_for_user(owner)
    assert length(tenants) == 2
  end

  test "add_member/3 allows assigning owner role to another user" do
    workspace = workspace_fixture()
    invited = user_fixture()

    assert {:ok, membership} =
             Tenancy.add_member(workspace.scope, workspace.tenant, %{
               email: invited.email,
               role: "owner"
             })

    assert membership.role == "owner"
  end

  test "add_member/3 allows multiple owners in the same tenant" do
    workspace = workspace_fixture()
    member1 = user_fixture()
    member2 = user_fixture()

    {:ok, m1} =
      Tenancy.add_member(workspace.scope, workspace.tenant, %{
        email: member1.email,
        role: "owner"
      })

    {:ok, m2} =
      Tenancy.add_member(workspace.scope, workspace.tenant, %{
        email: member2.email,
        role: "owner"
      })

    assert m1.role == "owner"
    assert m2.role == "owner"

    members = Tenancy.list_members(workspace.scope)
    owner_count = Enum.count(members, &(&1.role == "owner"))
    assert owner_count == 3
  end
end
