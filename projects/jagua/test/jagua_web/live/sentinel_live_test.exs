defmodule JaguaWeb.Live.SentinelLiveTest do
  use JaguaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Jagua.Factory

  defp log_in(conn, user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> put_session("user_id", user.id)
  end

  describe "show page — activity tab" do
    setup %{conn: conn} do
      user = create_user()
      project = create_project(owner: user)
      sentinel = create_sentinel(project: project, name: "My job", interval: :hourly)
      {:ok, conn: log_in(conn, user), project: project, sentinel: sentinel}
    end

    test "renders sentinel name and status", %{conn: conn, project: project, sentinel: sentinel} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/sentinels/#{sentinel.token}")
      assert html =~ "My job"
      assert html =~ "Pending"
    end

    test "renders heatmap", %{conn: conn, project: project, sentinel: sentinel} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.slug}/sentinels/#{sentinel.token}")
      assert html =~ "Activity"
    end

    test "can switch to setup tab", %{conn: conn, project: project, sentinel: sentinel} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/sentinels/#{sentinel.token}")

      html = view |> element("button", "Setup") |> render_click()
      assert html =~ sentinel.token
      assert html =~ "/in/"
    end

    test "can switch to settings tab", %{conn: conn, project: project, sentinel: sentinel} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/sentinels/#{sentinel.token}")

      html = view |> element("button", "Settings") |> render_click()
      assert html =~ "Edit sentinel"
    end
  end

  describe "settings tab — edit form" do
    setup %{conn: conn} do
      user = create_user()
      project = create_project(owner: user)
      sentinel = create_sentinel(project: project, name: "Original", interval: :hourly)
      {:ok, conn: log_in(conn, user), project: project, sentinel: sentinel}
    end

    test "updates sentinel name", %{conn: conn, project: project, sentinel: sentinel} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/sentinels/#{sentinel.token}")

      view |> element("button", "Settings") |> render_click()

      view
      |> form("form[phx-submit=update_sentinel]", %{name: "Renamed job"})
      |> render_submit()

      updated = Ash.get!(Jagua.Sentinels.Sentinel, sentinel.id, domain: Jagua.Sentinels)
      assert updated.name == "Renamed job"
    end
  end

  describe "pause / unpause" do
    setup %{conn: conn} do
      user = create_user()
      project = create_project(owner: user)
      sentinel = create_sentinel(project: project)
      {:ok, conn: log_in(conn, user), project: project, sentinel: sentinel}
    end

    test "pause changes status to paused", %{conn: conn, project: project, sentinel: sentinel} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/sentinels/#{sentinel.token}")
      view |> element("button", "Settings") |> render_click()
      view |> element("button", "Pause") |> render_click()

      updated = Ash.get!(Jagua.Sentinels.Sentinel, sentinel.id, domain: Jagua.Sentinels)
      assert updated.status == :paused
    end
  end
end
