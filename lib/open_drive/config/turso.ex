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
    turso_url = env.("TURSO_DATABASE_URL")
    turso_token = env.("TURSO_AUTH_TOKEN")

    if turso_url && String.starts_with?(turso_url, "libsql://") do
      Keyword.merge(
        [
          adapter: Ecto.Adapters.LibSql,
          uri: turso_url,
          auth_token: turso_token
        ],
        pool_opts(env, @default_pool_size)
      )
    else
      database_path =
        env.("DATABASE_PATH") ||
          raise """
          environment variable DATABASE_PATH or TURSO_DATABASE_URL is missing.
          """

      Keyword.merge(
        [
          adapter: Ecto.Adapters.LibSql,
          database: database_path
        ],
        pool_opts(env, 5)
      )
    end
  end

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
