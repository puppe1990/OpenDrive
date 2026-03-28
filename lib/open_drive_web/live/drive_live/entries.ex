defmodule OpenDriveWeb.DriveLive.Entries do
  @moduledoc false

  use OpenDriveWeb, :verified_routes

  @default_sort "modified_desc"

  def apply(children, controls) do
    children
    |> build_entries()
    |> filter_entries(controls)
    |> sort_entries(controls["sort"] || @default_sort)
  end

  def selected(entries, selected_keys) do
    selected_keys = selected_keys || MapSet.new()
    Enum.filter(entries, &MapSet.member?(selected_keys, entry_selection_key(&1)))
  end

  def selected_files(entries, selected_keys) do
    Enum.filter(selected(entries, selected_keys), &(&1.kind == :file))
  end

  def visible_images(entries), do: Enum.filter(entries, &(&1.preview == :image))
  def visible_videos(entries), do: Enum.filter(entries, &(&1.preview == :video))

  def selected_image(entries, selected_image_id) do
    Enum.find(visible_images(entries), &(&1.id == selected_image_id))
  end

  def selected_video(entries, selected_video_id) do
    Enum.find(visible_videos(entries), &(&1.id == selected_video_id))
  end

  def selected_image_id(entries, current_id) do
    if Enum.any?(entries, &(&1.preview == :image and &1.id == current_id)),
      do: current_id,
      else: nil
  end

  def selected_video_id(entries, current_id) do
    if Enum.any?(entries, &(&1.preview == :video and &1.id == current_id)),
      do: current_id,
      else: nil
  end

  def visible_entry_keys(entries) do
    entries
    |> Enum.map(&entry_selection_key/1)
    |> MapSet.new()
  end

  def sanitize_selected(entries, selected_keys) do
    MapSet.intersection(selected_keys || MapSet.new(), visible_entry_keys(entries))
  end

  def selected_all?(entries, selected_keys) do
    visible_keys = visible_entry_keys(entries)
    MapSet.size(visible_keys) > 0 and MapSet.equal?(visible_keys, selected_keys || MapSet.new())
  end

  def entry_selection_key(%{kind: kind, id: id}), do: "#{kind}:#{id}"

  defp build_entries(children) do
    folder_entries =
      Enum.map(children.folders, fn folder ->
        %{
          id: folder.id,
          kind: :folder,
          name: folder.name,
          content_type: "Folder",
          size: nil,
          updated_at: folder.updated_at,
          href: ~p"/app/folders/#{folder.id}",
          preview: :folder
        }
      end)

    file_entries =
      Enum.map(children.files, fn file ->
        %{
          id: file.id,
          kind: :file,
          name: file.name,
          content_type: file.file_object.content_type,
          size: file.file_object.size,
          updated_at: file.updated_at,
          href: ~p"/app/files/#{file.id}/download",
          preview:
            cond do
              image_file?(file) -> :image
              video_file?(file) -> :video
              true -> :file
            end
        }
      end)

    folder_entries ++ file_entries
  end

  defp filter_entries(entries, controls) do
    query = String.downcase(String.trim(controls["query"] || ""))
    type = controls["type"] || "all"

    Enum.filter(entries, fn entry ->
      matches_query? = query == "" or String.contains?(String.downcase(entry.name), query)
      matches_query? and matches_entry_type?(entry, type)
    end)
  end

  defp matches_entry_type?(_entry, "all"), do: true
  defp matches_entry_type?(entry, "folders"), do: entry.kind == :folder
  defp matches_entry_type?(entry, "files"), do: entry.kind == :file
  defp matches_entry_type?(entry, "images"), do: entry.preview == :image
  defp matches_entry_type?(entry, "videos"), do: entry.preview == :video

  defp sort_entries(entries, "name_asc"),
    do: Enum.sort_by(entries, &{entry_order(&1), String.downcase(&1.name)})

  defp sort_entries(entries, "name_desc"),
    do: Enum.sort_by(entries, &{entry_order(&1), String.downcase(&1.name)}, :desc)

  defp sort_entries(entries, "type_asc"),
    do:
      Enum.sort_by(
        entries,
        &{entry_order(&1), String.downcase(&1.content_type || ""), String.downcase(&1.name)}
      )

  defp sort_entries(entries, "type_desc"),
    do:
      Enum.sort_by(
        entries,
        &{entry_order(&1), String.downcase(&1.content_type || ""), String.downcase(&1.name)},
        :desc
      )

  defp sort_entries(entries, "size_desc"),
    do: Enum.sort_by(entries, &{entry_order(&1), -(&1.size || -1), String.downcase(&1.name)})

  defp sort_entries(entries, "size_asc"),
    do: Enum.sort_by(entries, &{entry_order(&1), &1.size || -1, String.downcase(&1.name)})

  defp sort_entries(entries, "modified_asc") do
    Enum.sort(entries, fn left, right ->
      cond do
        entry_order(left) != entry_order(right) ->
          entry_order(left) <= entry_order(right)

        DateTime.compare(left.updated_at, right.updated_at) == :lt ->
          true

        DateTime.compare(left.updated_at, right.updated_at) == :gt ->
          false

        true ->
          String.downcase(left.name) <= String.downcase(right.name)
      end
    end)
  end

  defp sort_entries(entries, _sort) do
    Enum.sort(entries, fn left, right ->
      cond do
        entry_order(left) != entry_order(right) ->
          entry_order(left) <= entry_order(right)

        DateTime.compare(left.updated_at, right.updated_at) == :gt ->
          true

        DateTime.compare(left.updated_at, right.updated_at) == :lt ->
          false

        true ->
          String.downcase(left.name) <= String.downcase(right.name)
      end
    end)
  end

  defp entry_order(%{kind: :folder}), do: 0
  defp entry_order(%{kind: :file}), do: 1

  defp image_file?(file), do: String.starts_with?(file.file_object.content_type || "", "image/")
  defp video_file?(file), do: String.starts_with?(file.file_object.content_type || "", "video/")
end
