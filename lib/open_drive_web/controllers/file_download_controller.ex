defmodule OpenDriveWeb.FileDownloadController do
  use OpenDriveWeb, :controller

  alias OpenDrive.Drive

  def show(conn, %{"id" => id}) do
    case Drive.download_url(conn.assigns.current_scope, id) do
      {:ok, url} ->
        redirect(conn, external: url)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "File not found.")
        |> redirect(to: ~p"/app")
    end
  end

  def zip(conn, params) do
    case build_zip(conn.assigns.current_scope, params["file_ids"]) do
      {:ok, filename, zip_binary} ->
        send_download(conn, {:binary, zip_binary},
          filename: filename,
          content_type: "application/zip"
        )

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Nenhum arquivo valido foi selecionado.")
        |> redirect(to: ~p"/app")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Nao foi possivel gerar o zip dos arquivos selecionados.")
        |> redirect(to: ~p"/app")
    end
  end

  defp build_zip(scope, file_ids) do
    with {:ok, sources} <- Drive.bulk_download_sources(scope, file_ids),
         {:ok, entries} <- build_zip_entries(sources) do
      filename = "opendrive-selecionados-#{Date.utc_today()}.zip"

      case :zip.create(String.to_charlist(filename), entries, [:memory]) do
        {:ok, {_name, zip_binary}} -> {:ok, filename, zip_binary}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp build_zip_entries(sources) do
    sources
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {source, index}, {:ok, acc} ->
      case fetch_binary(source.url) do
        {:ok, body} ->
          entry_name = unique_entry_name(source.name, index)
          {:cont, {:ok, [{String.to_charlist(entry_name), body} | acc]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, _} = error -> error
    end
  end

  defp fetch_binary("file://" <> path), do: File.read(path)

  defp fetch_binary(url) when is_binary(url) do
    :inets.start()
    :ssl.start()

    request = {String.to_charlist(url), []}

    case :httpc.request(:get, request, [], body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} -> {:ok, body}
      {:ok, {{_, status, _}, _headers, _body}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp unique_entry_name(name, index) do
    sanitized_name =
      name
      |> Path.basename()
      |> String.trim()
      |> case do
        "" -> "arquivo-#{index}"
        value -> value
      end

    root = Path.rootname(sanitized_name)
    ext = Path.extname(sanitized_name)
    "#{root}-#{index}#{ext}"
  end
end
