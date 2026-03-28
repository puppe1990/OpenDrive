defmodule OpenDrive.Storage.S3 do
  @behaviour OpenDrive.Storage

  def put_object(key, {:file, path}, opts) do
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")

    path
    |> ExAws.S3.Upload.stream_file()
    |> ExAws.S3.upload(OpenDrive.Storage.bucket(), key, content_type: content_type)
    |> ExAws.request()
  end

  def put_object(key, source, opts) do
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")

    OpenDrive.Storage.bucket()
    |> ExAws.S3.put_object(key, source, content_type: content_type)
    |> ExAws.request()
  end

  def presigned_upload_url(key, opts) do
    expires_in = Keyword.get(opts, :expires_in, 3600)
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")

    with {:ok, url} <-
           ExAws.Config.new(:s3)
           |> ExAws.S3.presigned_url(:put, OpenDrive.Storage.bucket(), key,
             expires_in: expires_in
           ) do
      {:ok, %{url: url, headers: %{"content-type" => content_type}}}
    end
  end

  def head_object(key) do
    case ExAws.S3.head_object(OpenDrive.Storage.bucket(), key) |> ExAws.request() do
      {:ok, response} ->
        headers = response_headers(response)

        {:ok,
         %{
           size: header_value(headers, "content-length") |> parse_integer_header(),
           content_type: header_value(headers, "content-type") || "application/octet-stream",
           etag: normalize_etag(header_value(headers, "etag"))
         }}

      {:error, {:http_error, 404, _}} ->
        {:error, :not_found}

      {:error, _} = error ->
        error

      error ->
        {:error, error}
    end
  end

  def delete_object(key) do
    case ExAws.S3.delete_object(OpenDrive.Storage.bucket(), key) |> ExAws.request() do
      {:ok, _} -> :ok
      error -> error
    end
  end

  def move_object(source_key, destination_key, _opts) do
    bucket = OpenDrive.Storage.bucket()

    with {:ok, copy_result} <-
           bucket
           |> ExAws.S3.put_object_copy(destination_key, bucket, source_key)
           |> ExAws.request(),
         :ok <- delete_object(source_key) do
      {:ok, %{copy_result: copy_result, destination_key: destination_key}}
    else
      {:error, _} = error -> error
      error -> {:error, error}
    end
  end

  def presigned_download_url(key, opts) do
    expires_in = Keyword.get(opts, :expires_in, 3600)

    ExAws.Config.new(:s3)
    |> ExAws.S3.presigned_url(:get, OpenDrive.Storage.bucket(), key, expires_in: expires_in)
  end

  defp response_headers(%{headers: headers}) when is_list(headers), do: headers
  defp response_headers(_), do: []

  defp header_value(headers, target_name) do
    target_name = String.downcase(target_name)

    Enum.find_value(headers, fn
      {name, value} when is_binary(name) and is_binary(value) ->
        if String.downcase(name) == target_name, do: value

      _ ->
        nil
    end)
  end

  defp parse_integer_header(nil), do: nil

  defp parse_integer_header(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} -> parsed
      :error -> nil
    end
  end

  defp normalize_etag(nil), do: nil
  defp normalize_etag(etag), do: String.trim(etag, "\"")
end
