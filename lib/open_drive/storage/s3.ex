defmodule OpenDrive.Storage.S3 do
  @behaviour OpenDrive.Storage

  def put_object(key, body, opts) do
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")

    OpenDrive.Storage.bucket()
    |> ExAws.S3.put_object(key, body, content_type: content_type)
    |> ExAws.request()
  end

  def delete_object(key) do
    case ExAws.S3.delete_object(OpenDrive.Storage.bucket(), key) |> ExAws.request() do
      {:ok, _} -> :ok
      error -> error
    end
  end

  def presigned_download_url(key, opts) do
    expires_in = Keyword.get(opts, :expires_in, 3600)

    ExAws.Config.new(:s3)
    |> ExAws.S3.presigned_url(:get, OpenDrive.Storage.bucket(), key, expires_in: expires_in)
  end
end
