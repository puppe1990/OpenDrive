defmodule OpenDrive.Accounts.Scope do
  @moduledoc """
  Carries the authenticated user and the active tenant membership.
  """

  alias OpenDrive.Tenancy.{Membership, Tenant}
  alias OpenDrive.Accounts.User

  defstruct user: nil, tenant: nil, membership: nil, memberships: []

  def for_user(user, opts \\ [])

  def for_user(%User{} = user, opts) do
    %__MODULE__{
      user: user,
      tenant: Keyword.get(opts, :tenant),
      membership: Keyword.get(opts, :membership),
      memberships: Keyword.get(opts, :memberships, [])
    }
  end

  def for_user(nil, _opts), do: nil

  def role(%__MODULE__{membership: %Membership{role: role}}), do: role
  def role(_), do: nil

  def tenant_id(%__MODULE__{tenant: %Tenant{id: tenant_id}}), do: tenant_id
  def tenant_id(_), do: nil

  def manage_members?(scope), do: role(scope) in ["owner", "admin"]
  def authenticated?(%__MODULE__{user: %User{}}), do: true
  def authenticated?(_), do: false
end
