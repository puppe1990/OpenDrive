defmodule OpenDrive.Accounts do
  @moduledoc """
  User registration, authentication and user-scoped helpers.
  """

  import Ecto.Query, warn: false

  alias OpenDrive.Accounts.{User, UserNotifier, UserToken}
  alias OpenDrive.Repo
  alias OpenDrive.Tenancy
  alias OpenDrive.Tenancy.Tenant

  def get_user_by_email(email) when is_binary(email), do: Repo.get_by(User, email: email)

  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  def get_user!(id), do: Repo.get!(User, id)

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second))
    |> Repo.insert()
  end

  def change_user_registration(user, attrs \\ %{}, opts \\ []) do
    User.registration_changeset(user, attrs, opts)
  end

  def change_user_registration_with_tenant(user, attrs \\ %{}, opts \\ []) do
    opts
    |> Keyword.put_new(:validate_tenant, true)
    |> then(&User.registration_changeset(user, attrs, &1))
  end

  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  def change_user_email(user, attrs \\ %{}, opts \\ []),
    do: User.email_changeset(user, attrs, opts)

  def change_user_password(user, attrs \\ %{}, opts \\ []),
    do: User.password_changeset(user, attrs, opts)

  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transaction(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        user
      else
        _ -> Repo.rollback(:transaction_aborted)
      end
    end)
    |> normalize_transaction_result()
  end

  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")
    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  def deliver_login_instructions(%User{} = user, login_url_fun)
      when is_function(login_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, login_url_fun.(encoded_token))
  end

  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)

    case Repo.one(query) do
      {user, inserted_at} ->
        {user, inserted_at}

      nil ->
        nil
    end
  end

  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      {user, token_record} ->
        Repo.delete!(token_record)
        {:ok, {user_with_authenticated_at(user, token_record.inserted_at), []}}

      nil ->
        {:error, :not_found}
    end
  end

  def register_user_with_tenant(user_attrs, tenant_attrs) do
    user_attrs_with_tenant = put_tenant_name(user_attrs, tenant_attrs)
    registration_changeset = change_user_registration_with_tenant(%User{}, user_attrs_with_tenant)

    case registration_changeset.valid? do
      true ->
        user_attrs_with_tenant
        |> register_user_with_tenant_transaction(user_attrs, tenant_attrs)
        |> normalize_transaction_result()

      false ->
        {:error, %{registration_changeset | action: :insert}}
    end
  end

  def build_scope(user, tenant_id \\ nil)

  def build_scope(nil, _tenant_id), do: nil

  def build_scope(%User{} = user, tenant_id) do
    Tenancy.build_scope(user, tenant_id)
  end

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transaction(fn ->
      case Repo.update(changeset) do
        {:ok, user} ->
          tokens = Repo.all(from(UserToken, where: [user_id: ^user.id]))
          Repo.delete_all(from(UserToken, where: [user_id: ^user.id]))
          {user, tokens}

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> normalize_transaction_result()
  end

  defp register_user_with_tenant_transaction(user_attrs_with_tenant, user_attrs, tenant_attrs) do
    Repo.transaction(fn ->
      with {:ok, user} <- register_user(user_attrs),
           {:ok, tenant} <- Tenancy.create_tenant_with_owner(user, tenant_attrs) do
        %{user: user, tenant: tenant}
      else
        {:error, %Ecto.Changeset{} = changeset} ->
          Repo.rollback(remap_registration_error(user_attrs_with_tenant, changeset))

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  defp user_with_authenticated_at(user, inserted_at) do
    %{user | authenticated_at: inserted_at}
  end

  defp remap_registration_error(user_attrs, %Ecto.Changeset{data: %Tenant{}} = changeset) do
    base_changeset =
      change_user_registration_with_tenant(%User{}, user_attrs, validate_unique: false)

    mapped_changeset =
      Enum.reduce(changeset.errors, base_changeset, fn
        {:name, {message, opts}}, acc ->
          Ecto.Changeset.add_error(acc, :tenant_name, message, opts)

        {:slug, {message, opts}}, acc ->
          Ecto.Changeset.add_error(acc, :tenant_name, message, opts)

        _, acc ->
          acc
      end)

    %{mapped_changeset | action: :insert}
  end

  defp remap_registration_error(_user_attrs, %Ecto.Changeset{} = changeset), do: changeset

  defp put_tenant_name(user_attrs, tenant_attrs) do
    tenant_name = Map.get(tenant_attrs, :name) || Map.get(tenant_attrs, "name")

    cond do
      is_nil(tenant_name) ->
        user_attrs

      is_map_key(user_attrs, :tenant_name) ->
        user_attrs

      is_map_key(user_attrs, "tenant_name") ->
        user_attrs

      true ->
        Map.put(user_attrs, :tenant_name, tenant_name)
    end
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, reason}), do: {:error, reason}
end
