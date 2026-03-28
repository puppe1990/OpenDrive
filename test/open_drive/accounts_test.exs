defmodule OpenDrive.AccountsTest do
  use OpenDrive.DataCase

  alias OpenDrive.Accounts
  alias OpenDrive.Accounts.User

  import OpenDrive.AccountsFixtures

  test "register_user/1 creates a password-based user" do
    {:ok, user} = Accounts.register_user(valid_user_attributes())

    assert %User{} = user
    assert user.hashed_password
    assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
  end

  test "register_user_with_tenant/2 provisions the workspace owner" do
    {:ok, %{user: user, tenant: tenant}} =
      Accounts.register_user_with_tenant(valid_user_attributes(), %{name: "Acme Files"})

    scope = Accounts.build_scope(user, tenant.id)

    assert scope.tenant.name == "Acme Files"
    assert scope.membership.role == "owner"
  end

  test "register_user_with_tenant/2 allows the same workspace name for different users" do
    {:ok, %{tenant: first_tenant}} =
      Accounts.register_user_with_tenant(valid_user_attributes(), %{name: "Arquivos Pessoais"})

    {:ok, %{tenant: second_tenant}} =
      Accounts.register_user_with_tenant(valid_user_attributes(), %{name: "Arquivos Pessoais"})

    assert first_tenant.name == second_tenant.name
    assert first_tenant.id != second_tenant.id
  end

  test "register_user_with_tenant/2 rejects duplicate workspace names for the same user" do
    user = user_fixture()

    assert {:ok, _tenant} = OpenDrive.Tenancy.create_tenant_with_owner(user, %{name: "Equipe"})

    assert {:error, changeset} =
             OpenDrive.Tenancy.create_tenant_with_owner(user, %{name: "Equipe"})

    assert "has already been taken" in errors_on(changeset).slug
  end

  test "generate_user_session_token/1 round-trips the session" do
    user = user_fixture()
    token = Accounts.generate_user_session_token(user)

    assert {scoped_user, _inserted_at} = Accounts.get_user_by_session_token(token)
    assert scoped_user.id == user.id
  end
end
