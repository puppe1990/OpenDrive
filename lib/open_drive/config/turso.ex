defmodule OpenDrive.Config.Turso do
  @moduledoc """
  Builds Ecto LibSQL repo configuration for production.
  """

  @doc """
  Returns keyword list suitable for `config :open_drive, OpenDrive.Repo, ...`.
  """
  @default_pool_size 15
  @default_queue_target 5_000
  @default_queue_interval 1_000
  @default_timeout 15_000

  def repo_config(env \\ &System.get_env/1) when is_function(env, 1) do
    database_path = blank_to_nil(env.("DATABASE_PATH"))
    turso_url = env.("TURSO_DATABASE_URL")
    turso_token = env.("TURSO_AUTH_TOKEN")

    cond do
      is_binary(database_path) ->
        Keyword.merge(
          [
            adapter: Ecto.Adapters.LibSql,
            database: database_path,
            journal_mode: :wal
          ],
          pool_opts(env, 5)
        )

      is_binary(turso_url) and String.starts_with?(turso_url, "libsql://") ->
        Keyword.merge(
          [
            adapter: Ecto.Adapters.LibSql,
            uri: turso_url,
            auth_token: turso_token
          ],
          pool_opts(env, @default_pool_size)
        )

      true ->
        raise """
        environment variable DATABASE_PATH or TURSO_DATABASE_URL is missing.
        """
    end
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp pool_opts(env, default_pool_size) do
    pool_size = String.to_integer(env.("POOL_SIZE") || Integer.to_string(default_pool_size))

    [
      pool_size: pool_size,
      queue_target: @default_queue_target,
      queue_interval: @default_queue_interval,
      timeout: @default_timeout
    ]
  end
end
