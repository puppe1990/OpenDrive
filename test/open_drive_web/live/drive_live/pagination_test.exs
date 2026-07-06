defmodule OpenDriveWeb.DriveLive.PaginationTest do
  use ExUnit.Case, async: true

  alias OpenDriveWeb.DriveLive.Pagination

  test "returns the first page of entries" do
    entries = Enum.map(1..120, &%{id: &1})

    {page_entries, meta} = Pagination.paginate(entries, 1)

    assert length(page_entries) == Pagination.per_page()
    assert meta.page == 1
    assert meta.total == 120
    assert meta.total_pages == 2
    assert meta.has_prev? == false
    assert meta.has_next? == true
  end

  test "returns the second page of entries" do
    entries = Enum.map(1..120, &%{id: &1})

    {page_entries, meta} = Pagination.paginate(entries, 2)

    assert length(page_entries) == 20
    assert meta.page == 2
    assert meta.has_prev? == true
    assert meta.has_next? == false
  end

  test "clamps invalid page numbers" do
    entries = Enum.map(1..5, &%{id: &1})

    {page_entries, meta} = Pagination.paginate(entries, 99)

    assert length(page_entries) == 5
    assert meta.page == 1
  end

  test "parses page values safely" do
    assert Pagination.parse_page("2") == 2
    assert Pagination.parse_page("0") == 1
    assert Pagination.parse_page("abc") == 1
    assert Pagination.parse_page(nil) == 1
  end
end
