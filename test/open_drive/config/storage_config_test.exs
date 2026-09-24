defmodule OpenDrive.Config.StorageConfigTest do
  use ExUnit.Case, async: true

  alias OpenDrive.Config.Storage
  alias OpenDrive.Storage.Fake
  alias OpenDrive.Storage.S3

  test "defaults production to Backblaze B2" do
    env = fn
      "B2_APPLICATION_KEY_ID" -> "b2-key-id"
      "B2_APPLICATION_KEY" -> "b2-application-key"
      "B2_BUCKET" -> "open-drive-phoenix"
      _ -> nil
    end

    assert %{
             adapter: S3,
             bucket: "open-drive-phoenix",
             ex_aws: ex_aws,
             ex_aws_service: ex_aws_service
           } = Storage.provider_settings(env, :prod)

    assert ex_aws == [
             access_key_id: "b2-key-id",
             secret_access_key: "b2-application-key",
             region: "us-east-1"
           ]

    assert ex_aws_service == [scheme: "https://", host: "s3.us-east-005.backblazeb2.com"]
  end

  test "keeps AWS S3 when the adapter is s3" do
    env = fn
      "OPEN_DRIVE_STORAGE_ADAPTER" -> "s3"
      "AWS_S3_BUCKET" -> "open-drive-dev-840298254452"
      "AWS_REGION" -> "us-east-1"
      _ -> nil
    end

    assert %{
             adapter: S3,
             bucket: "open-drive-dev-840298254452",
             ex_aws: [],
             ex_aws_service: []
           } = Storage.provider_settings(env, :prod)
  end

  test "honours B2 region and endpoint overrides" do
    env = fn
      "OPEN_DRIVE_STORAGE_ADAPTER" -> "b2"
      "B2_REGION" -> "us-west-004"
      "B2_ENDPOINT" -> "s3.eu-central-003.backblazeb2.com"
      "B2_APPLICATION_KEY_ID" -> "key-id"
      "B2_APPLICATION_KEY" -> "app-key"
      "B2_BUCKET" -> "bucket-a"
      _ -> nil
    end

    assert %{bucket: "bucket-a", ex_aws_service: ex_aws_service} =
             Storage.provider_settings(env, :prod)

    assert ex_aws_service == [scheme: "https://", host: "s3.eu-central-003.backblazeb2.com"]
  end

  test "keeps the custom S3 host when provided" do
    env = fn
      "OPEN_DRIVE_STORAGE_ADAPTER" -> "s3"
      "AWS_S3_HOST" -> "minio.internal"
      "AWS_S3_SCHEME" -> "http://"
      "AWS_S3_PORT" -> "9000"
      _ -> nil
    end

    assert %{ex_aws_service: ex_aws_service} = Storage.provider_settings(env, :dev)

    assert ex_aws_service == [scheme: "http://", host: "minio.internal", port: "9000"]
  end

  test "falls back to the fake adapter outside production" do
    enabled = fn
      "B2_APPLICATION_KEY_ID" -> "key-id"
      "B2_APPLICATION_KEY" -> "app-key"
      "B2_BUCKET" -> "bucket-a"
      _ -> nil
    end

    assert %{adapter: Fake, bucket: "open-drive-dev", ex_aws: [], ex_aws_service: []} =
             Storage.provider_settings(enabled, :dev)

    assert %{adapter: Fake} = Storage.provider_settings(fn _ -> nil end, :test)
  end

  test "raises when B2 configuration is incomplete" do
    env = fn
      "B2_APPLICATION_KEY_ID" -> "key-id"
      "B2_APPLICATION_KEY" -> "app-key"
      _ -> nil
    end

    assert_raise RuntimeError, ~r/B2_BUCKET is required/, fn ->
      Storage.provider_settings(env, :prod)
    end
  end
end
