defmodule OpenDrive.Storage do
  @moduledoc """
  Storage facade for file blobs.
  """

  @callback put_object(binary(), binary(), keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback delete_object(binary()) :: :ok | {:error, term()}
  @callback move_object(binary(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback presigned_download_url(binary(), keyword()) :: {:ok, binary()} | {:error, term()}

  def put_object(key, body, opts \\ []) do
    adapter().put_object(key, body, opts)
  end

  def delete_object(key) do
    adapter().delete_object(key)
  end

  def move_object(source_key, destination_key, opts \\ []) do
    adapter().move_object(source_key, destination_key, opts)
  end

  def presigned_download_url(key, opts \\ []) do
    adapter().presigned_download_url(key, opts)
  end

  def bucket, do: config()[:bucket]

  defp adapter, do: config()[:adapter]
  defp config, do: Application.fetch_env!(:open_drive, __MODULE__)
end
