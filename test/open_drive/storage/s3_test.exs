defmodule OpenDrive.Storage.S3Test do
  use ExUnit.Case, async: false

  alias OpenDrive.Storage.S3

  setup do
    previous = %{
      access_key_id: Application.get_env(:ex_aws, :access_key_id),
      secret_access_key: Application.get_env(:ex_aws, :secret_access_key),
      region: Application.get_env(:ex_aws, :region)
    }

    Application.put_env(:ex_aws, :access_key_id, "AKIATEST")
    Application.put_env(:ex_aws, :secret_access_key, "test-secret")
    Application.put_env(:ex_aws, :region, "us-east-1")

    on_exit(fn ->
      restore(:access_key_id, previous.access_key_id)
      restore(:secret_access_key, previous.secret_access_key)
      restore(:region, previous.region)
    end)

    :ok
  end

  test "signs the content-type header on presigned PUT URLs" do
    assert {:ok, %{url: url, headers: headers}} =
             S3.presigned_upload_url("tenant/file.pdf", content_type: "application/pdf")

    assert headers["content-type"] == "application/pdf"

    signed_headers =
      url
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()
      |> Map.fetch!("X-Amz-SignedHeaders")

    assert signed_headers =~ "content-type"
  end

  defp restore(key, nil), do: Application.delete_env(:ex_aws, key)
  defp restore(key, value), do: Application.put_env(:ex_aws, key, value)
end
