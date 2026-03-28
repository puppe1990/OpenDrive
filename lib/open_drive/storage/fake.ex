defmodule OpenDrive.Storage.Fake do
  @behaviour OpenDrive.Storage

  def put_object(key, {:file, source_path}, _opts) do
    path = object_path(key)
    File.mkdir_p!(Path.dirname(path))

    case File.cp(source_path, path) do
      :ok -> {:ok, %{etag: file_md5(path)}}
      error -> error
    end
  end

  def put_object(key, body, _opts) when is_binary(body) do
    path = object_path(key)
    File.mkdir_p!(Path.dirname(path))

    case File.write(path, body) do
      :ok -> {:ok, %{etag: :crypto.hash(:md5, body) |> Base.encode16(case: :lower)}}
      error -> error
    end
  end

  def presigned_upload_url(key, opts) do
    {:ok,
     %{
       url: "file://" <> object_path(key),
       headers: %{"content-type" => Keyword.get(opts, :content_type, "application/octet-stream")}
     }}
  end

  def head_object(key) do
    path = object_path(key)

    with {:ok, %File.Stat{size: size}} <- File.stat(path) do
      {:ok,
       %{
         size: size,
         content_type: MIME.from_path(path) || "application/octet-stream",
         etag: file_md5(path)
       }}
    else
      {:error, :enoent} -> {:error, :not_found}
      error -> error
    end
  end

  def delete_object(key) do
    case File.rm(object_path(key)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      error -> error
    end
  end

  def move_object(source_key, destination_key, _opts) do
    source_path = object_path(source_key)
    destination_path = object_path(destination_key)
    File.mkdir_p!(Path.dirname(destination_path))

    case File.rename(source_path, destination_path) do
      :ok -> {:ok, %{source_key: source_key, destination_key: destination_key}}
      error -> error
    end
  end

  def presigned_download_url(key, _opts) do
    {:ok, "file://" <> object_path(key)}
  end

  defp object_path(key) do
    Path.join([System.tmp_dir!(), "open_drive_storage", OpenDrive.Storage.bucket(), key])
  end

  defp file_md5(path) do
    path
    |> File.stream!([], 1_048_576)
    |> Enum.reduce(:crypto.hash_init(:md5), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end
end
