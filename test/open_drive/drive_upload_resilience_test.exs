defmodule OpenDrive.DriveUploadResilienceTest do
  use ExUnit.Case, async: true

  alias OpenDrive.Drive

  test "limits concurrent direct uploads to four" do
    assert Drive.max_concurrent_uploads() == 4
  end

  test "with_db_rescue returns db_busy on connection errors" do
    assert {:error, :db_busy} =
             Drive.with_db_rescue(fn ->
               raise %DBConnection.ConnectionError{message: "connection not available"}
             end)
  end

  test "with_db_rescue passes through successful results" do
    assert {:ok, :saved} = Drive.with_db_rescue(fn -> {:ok, :saved} end)
  end

  test "with_db_rescue passes through tagged errors" do
    assert {:error, :not_found} = Drive.with_db_rescue(fn -> {:error, :not_found} end)
  end
end
