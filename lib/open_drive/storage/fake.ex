defmodule OpenDrive.Storage.Fake do
  @behaviour OpenDrive.Storage

  def put_object(key, body, _opts) do
    path = object_path(key)
    File.mkdir_p!(Path.dirname(path))

    case File.write(path, body) do
      :ok -> {:ok, %{etag: :crypto.hash(:md5, body) |> Base.encode16(case: :lower)}}
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

  def presigned_download_url(key, _opts) do
    {:ok, "file://" <> object_path(key)}
  end

  defp object_path(key) do
    Path.join([System.tmp_dir!(), "open_drive_storage", OpenDrive.Storage.bucket(), key])
  end
end
