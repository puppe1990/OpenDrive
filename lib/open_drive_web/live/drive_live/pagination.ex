defmodule OpenDriveWeb.DriveLive.Pagination do
  @moduledoc false

  @per_page 100

  def per_page, do: @per_page

  def paginate(entries, page) when is_list(entries) do
    total = length(entries)
    total_pages = total_pages(total)
    page = normalize_page(parse_page(page), total_pages)

    page_entries =
      entries
      |> Enum.drop((page - 1) * @per_page)
      |> Enum.take(@per_page)

    meta = %{
      page: page,
      per_page: @per_page,
      total: total,
      total_pages: total_pages,
      has_prev?: page > 1,
      has_next?: page < total_pages
    }

    {page_entries, meta}
  end

  def total_pages(0), do: 1

  def total_pages(total) when total > 0 do
    (total + @per_page - 1) |> div(@per_page) |> max(1)
  end

  def parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {number, ""} when number > 0 -> number
      _ -> 1
    end
  end

  def parse_page(page) when is_integer(page) and page > 0, do: page
  def parse_page(_), do: 1

  defp normalize_page(page, total_pages), do: page |> max(1) |> min(total_pages)
end
