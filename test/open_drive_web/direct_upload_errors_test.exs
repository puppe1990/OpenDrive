defmodule OpenDriveWeb.DirectUploadErrorsTest do
  use ExUnit.Case, async: true

  alias OpenDriveWeb.DirectUploadErrors

  test "db_busy maps to a service unavailable response" do
    assert {503, %{"error" => message}} = DirectUploadErrors.response(:db_busy)
    assert message =~ "busy"
    assert message =~ "retry"
  end
end
