defmodule OpenDrive.Config.Storage do
  @moduledoc """
  Builds storage adapter configuration for Backblaze B2, AWS S3, or the fake adapter.
  """

  @doc """
  Returns the storage settings for the selected provider.

  The provider comes from `OPEN_DRIVE_STORAGE_ADAPTER` (`b2`, `s3`, or any other
  value for the fake adapter). When unset, production defaults to Backblaze B2
  while other environments keep the fake adapter.

  The returned map holds the adapter and bucket for `config :open_drive,
  OpenDrive.Storage`, the shared `ExAws` keys, and the service level
  `config :ex_aws, :s3` overrides required by the provider.
  """
  @default_provider "b2"
  @default_b2_region "us-east-005"
  @default_bucket "open-drive-dev"

  # ExAws validates the region against the AWS partition endpoint table, which
  # rejects B2 regions. Requests to B2 are therefore signed with an AWS region:
  # B2 ignores the signing region and routes by the configured endpoint.
  @b2_signing_region "us-east-1"

  def provider_settings(env \\ &System.get_env/1, config_env) when is_function(env, 1) do
    case provider(env, config_env) do
      "b2" -> b2_settings(env)
      "s3" -> s3_settings(env)
      _ -> fake_settings(env)
    end
  end

  defp provider(env, config_env) do
    env.("OPEN_DRIVE_STORAGE_ADAPTER") || default_provider(config_env)
  end

  defp default_provider(:prod), do: @default_provider
  defp default_provider(_config_env), do: "fake"

  defp b2_settings(env) do
    region = env.("B2_REGION") || @default_b2_region
    endpoint = env.("B2_ENDPOINT") || "s3.#{region}.backblazeb2.com"

    %{
      adapter: OpenDrive.Storage.S3,
      bucket: required(env, "B2_BUCKET"),
      ex_aws: [
        access_key_id: required(env, "B2_APPLICATION_KEY_ID"),
        secret_access_key: required(env, "B2_APPLICATION_KEY"),
        region: @b2_signing_region
      ],
      ex_aws_service: [scheme: "https://", host: endpoint]
    }
  end

  defp s3_settings(env) do
    %{
      adapter: OpenDrive.Storage.S3,
      bucket: env.("AWS_S3_BUCKET") || @default_bucket,
      ex_aws: [],
      ex_aws_service: aws_s3_host(env)
    }
  end

  defp fake_settings(env) do
    %{
      adapter: OpenDrive.Storage.Fake,
      bucket: env.("AWS_S3_BUCKET") || @default_bucket,
      ex_aws: [],
      ex_aws_service: []
    }
  end

  defp aws_s3_host(env) do
    case env.("AWS_S3_HOST") do
      nil ->
        []

      host ->
        [
          scheme: env.("AWS_S3_SCHEME") || "https://",
          host: host,
          port: env.("AWS_S3_PORT")
        ]
    end
  end

  defp required(env, key) do
    case env.(key) do
      value when is_binary(value) and value != "" ->
        value

      _ ->
        raise """
        #{key} is required when OPEN_DRIVE_STORAGE_ADAPTER is set to "b2".
        """
    end
  end
end
