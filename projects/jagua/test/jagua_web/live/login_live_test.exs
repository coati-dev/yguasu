defmodule JaguaWeb.Live.LoginLiveTest do
  use JaguaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Jagua.Factory

  describe "login page" do
    test "renders sign in form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/login")
      assert html =~ "Sign in"
      assert html =~ "Send login link"
    end

    test "redirects authenticated users away", %{conn: conn} do
      user = create_user()

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> put_session("user_id", user.id)

      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/login")
      assert path =~ "/dashboard"
    end
  end

  describe "submit form" do
    test "shows confirmation message with valid email", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/login")

      html =
        view
        |> form("form", %{"email" => "new@example.com"})
        |> render_submit()

      assert html =~ "Check your inbox"
      assert html =~ "new@example.com"
    end

    test "shows error with invalid email", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/login")

      html =
        view
        |> form("form", %{"email" => "notanemail"})
        |> render_submit()

      assert html =~ "valid email address"
    end

    test "creates a new user for an unknown email", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/login")

      view
      |> form("form", %{"email" => "brand_new@example.com"})
      |> render_submit()

      assert Jagua.Accounts.User
             |> Ash.Query.for_read(:by_email, %{email: "brand_new@example.com"})
             |> Ash.read_one!(domain: Jagua.Accounts)
    end
  end

  describe "confirm magic link" do
    test "logs in with a valid token and redirects to dashboard", %{conn: conn} do
      user = create_user()

      raw_token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
      token_hash = :crypto.hash(:sha256, raw_token) |> Base.encode16(case: :lower)
      expires_at = DateTime.add(DateTime.utc_now(), 15, :minute)

      Jagua.Accounts.MagicLink
      |> Ash.Changeset.for_create(:create, %{
        user_id: user.id,
        token_hash: token_hash,
        expires_at: expires_at
      })
      |> Ash.create!(domain: Jagua.Accounts)

      conn = get(conn, ~p"/auth/confirm/#{raw_token}")

      assert redirected_to(conn) == ~p"/dashboard"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome"
    end

    test "rejects an invalid token and redirects to login", %{conn: conn} do
      conn = get(conn, ~p"/auth/confirm/totallyfaketoken")

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or has expired"
    end

    test "rejects an already-used token", %{conn: conn} do

      user = create_user()

      raw_token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
      token_hash = :crypto.hash(:sha256, raw_token) |> Base.encode16(case: :lower)
      expires_at = DateTime.add(DateTime.utc_now(), 15, :minute)

      magic_link =
        Jagua.Accounts.MagicLink
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          token_hash: token_hash,
          expires_at: expires_at
        })
        |> Ash.create!(domain: Jagua.Accounts)

      magic_link
      |> Ash.Changeset.for_update(:consume, %{})
      |> Ash.update!(domain: Jagua.Accounts)

      conn = get(conn, ~p"/auth/confirm/#{raw_token}")

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or has expired"
    end
  end

  describe "logout" do
    test "clears session and redirects to login", %{conn: conn} do
      user = create_user()

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> put_session("user_id", user.id)

      conn = delete(conn, ~p"/auth/logout")

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "logged out"
      refute get_session(conn, "user_id")
    end
  end
end
