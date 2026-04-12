defmodule JaguaWeb.Live.DashboardLiveTest do
  use JaguaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Jagua.Factory

  defp log_in(conn, user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> put_session("user_id", user.id)
  end

  describe "unauthenticated" do
    test "redirects to login", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/dashboard")
      assert path =~ "/login"
    end
  end

  describe "authenticated" do
    setup %{conn: conn} do
      user = create_user()
      {:ok, conn: log_in(conn, user), user: user}
    end

    test "renders dashboard with no projects", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "No projects yet"
    end

    test "renders project list", %{conn: conn, user: user} do
      create_project(owner: user, name: "Alpha")
      create_project(owner: user, name: "Beta")

      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Alpha"
      assert html =~ "Beta"
    end

    test "shows user email in header", %{conn: conn, user: user} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ to_string(user.email)
    end

    test "has a link to new project page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ ~p"/projects/new"
    end
  end
end
