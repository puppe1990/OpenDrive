defmodule OpenDriveWeb.UserLive.RegistrationTest do
  use OpenDriveWeb.ConnCase

  import OpenDrive.AccountsFixtures
  import Phoenix.LiveViewTest

  alias OpenDrive.Accounts

  test "registers a user and provisions a tenant", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/register")

    form =
      form(lv, "#registration_form",
        user: %{
          tenant_name: "Docs Squad",
          email: "owner@example.com",
          password: "super secure 123",
          password_confirmation: "super secure 123"
        }
      )

    render_submit(form)

    assert Accounts.get_user_by_email("owner@example.com")

    assert Accounts.get_user_by_email("owner@example.com")
           |> Accounts.build_scope()
           |> Map.get(:tenant)
           |> Map.get(:name) == "Docs Squad"
  end

  test "allows the same workspace name for a different email", %{conn: conn} do
    workspace_fixture(%{tenant_name: "Docs Squad"})

    {:ok, lv, _html} = live(conn, ~p"/users/register")

    form =
      form(lv, "#registration_form",
        user: %{
          tenant_name: "Docs Squad",
          email: "second-owner@example.com",
          password: "super secure 123",
          password_confirmation: "super secure 123"
        }
      )

    render_submit(form)

    assert Accounts.get_user_by_email("second-owner@example.com")
  end
end
