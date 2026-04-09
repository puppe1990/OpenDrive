defmodule OpenDriveWeb.FileDownloadController do
  use OpenDriveWeb, :controller
  require Logger

  alias OpenDrive.Drive

  @max_zip_entries 100
  @max_zip_total_bytes 500 * 1024 * 1024

  def show(conn, %{"id" => id}) do
    case Drive.download_url(conn.assigns.current_scope, id) do
      {:ok, "file://" <> path} ->
        case serve_local_file(conn, path) do
          {:error, :not_found} ->
            conn
            |> put_flash(:error, gettext("File not found."))
            |> redirect(to: ~p"/app")

          conn ->
            conn
        end

      {:ok, url} ->
        redirect(conn, external: url)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, gettext("File not found."))
        |> redirect(to: ~p"/app")
    end
  end

  defp serve_local_file(conn, path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: file_size}} ->
        content_type = MIME.from_path(path) || "application/octet-stream"

        conn =
          conn
          |> put_resp_header("content-type", content_type)
          |> put_resp_header("accept-ranges", "bytes")

        case get_req_header(conn, "range") do
          ["bytes=" <> range] ->
            case parse_range(range, file_size) do
              {:ok, range_start, range_end} ->
                length = range_end - range_start + 1

                conn
                |> put_resp_header("content-range", "bytes #{range_start}-#{range_end}/#{file_size}")
                |> send_file(206, path, range_start, length)

              :error ->
                conn
                |> put_resp_header("content-range", "bytes */#{file_size}")
                |> send_resp(416, "")
            end

          _ ->
            send_file(conn, 200, path)
        end

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        Logger.warning("failed to read local download blob at #{path}: #{inspect(reason)}")
        {:error, :not_found}
    end
  end

  defp parse_range(range, file_size) do
    case String.split(range, ",", parts: 2) do
      [single_range] -> parse_single_range(single_range, file_size)
      _ -> :error
    end
  end

  defp parse_single_range("-" <> suffix, file_size) do
    case Integer.parse(suffix) do
      {length, ""} when length > 0 and length <= file_size ->
        {:ok, file_size - length, file_size - 1}

      _ ->
        :error
    end
  end

  defp parse_single_range(range, file_size) do
    case String.split(range, "-", parts: 2) do
      [start_part, ""] ->
        with {range_start, ""} <- Integer.parse(start_part),
             true <- range_start >= 0 and range_start < file_size do
          {:ok, range_start, file_size - 1}
        else
          _ -> :error
        end

      [start_part, end_part] ->
        with {range_start, ""} <- Integer.parse(start_part),
             {range_end, ""} <- Integer.parse(end_part),
             true <- range_start >= 0 and range_start <= range_end and range_end < file_size do
          {:ok, range_start, range_end}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  def zip(conn, params) do
    case build_zip(conn.assigns.current_scope, params["file_ids"]) do
      {:ok, filename, zip_path, cleanup_dir} ->
        schedule_zip_cleanup(cleanup_dir)

        send_download(conn, {:file, zip_path},
          filename: filename,
          content_type: "application/zip"
        )

      {:error, :not_found} ->
        conn
        |> put_flash(:error, gettext("No valid file was selected."))
        |> redirect(to: ~p"/app")

      {:error, :zip_limit_exceeded} ->
        conn
        |> put_flash(
          :error,
          gettext("ZIP download is limited to 100 files and 500 MB per request.")
        )
        |> redirect(to: ~p"/app")

      {:error, _reason} ->
        conn
        |> put_flash(:error, gettext("Unable to generate a ZIP for the selected files."))
        |> redirect(to: ~p"/app")
    end
  end

  defp build_zip(scope, file_ids) do
    with {:ok, sources} <- Drive.bulk_download_sources(scope, file_ids),
         :ok <- validate_zip_limits(sources),
         {:ok, filename, zip_path, cleanup_dir} <- build_zip_file(sources),
         true <- File.exists?(zip_path) do
      {:ok, filename, zip_path, cleanup_dir}
    else
      false -> {:error, :zip_not_created}
      {:error, _} = error -> error
    end
  end

  defp build_zip_file(sources) do
    filename = "opendrive-selecionados-#{Date.utc_today()}.zip"

    temp_dir =
      Path.join(System.tmp_dir!(), "open_drive_zip_#{System.unique_integer([:positive])}")

    zip_path = Path.join(temp_dir, filename)

    with :ok <- File.mkdir_p(temp_dir),
         {:ok, entry_names} <- stage_zip_entries(sources, temp_dir) do
      case :zip.create(String.to_charlist(zip_path), Enum.map(entry_names, &String.to_charlist/1),
             cwd: String.to_charlist(temp_dir)
           ) do
        {:ok, _zip_name} -> {:ok, filename, zip_path, temp_dir}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp stage_zip_entries(sources, temp_dir) do
    sources
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, &stage_zip_entry(&1, &2, temp_dir))
    |> case do
      {:ok, entry_names} -> {:ok, Enum.reverse(entry_names)}
      {:error, _} = error -> error
    end
  end

  defp stage_zip_entry({source, index}, {:ok, acc}, temp_dir) do
    with {:ok, body} <- fetch_binary(source.url),
         :ok <- write_zip_entry(body, source.name, index, temp_dir) do
      entry_name = unique_entry_name(source.name, index)
      {:cont, {:ok, [entry_name | acc]}}
    else
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp write_zip_entry(body, source_name, index, temp_dir) do
    source_name
    |> unique_entry_name(index)
    |> then(&Path.join(temp_dir, &1))
    |> File.write(body)
  end

  defp validate_zip_limits(sources) do
    entry_count = length(sources)
    total_bytes = Enum.reduce(sources, 0, &(&1.size + &2))

    cond do
      entry_count == 0 -> {:error, :not_found}
      entry_count > @max_zip_entries -> {:error, :zip_limit_exceeded}
      total_bytes > @max_zip_total_bytes -> {:error, :zip_limit_exceeded}
      true -> :ok
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

  defp schedule_zip_cleanup(cleanup_dir) do
    Task.start(fn ->
      Process.sleep(5_000)

      case File.rm_rf(cleanup_dir) do
        {:ok, _paths} -> :ok
        {:error, reason, _path} -> Logger.warning("zip cleanup failed: #{inspect(reason)}")
      end
    end)
  end
end
