defmodule OpenDriveWeb.UserLive.SettingsTest do
  use OpenDriveWeb.ConnCase

  import Phoenix.LiveViewTest

  @tag token_authenticated_at: DateTime.add(DateTime.utc_now(), -30, :minute)
  setup :register_and_log_in_user

  test "allows opening settings with an older authenticated session", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/users/settings")

    assert html =~ "Account Settings"
    assert html =~ "Change Email"
    assert html =~ "Save Password"
  end
end
