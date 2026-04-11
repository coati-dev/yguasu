defmodule JaguaWeb.CheckInControllerTest do
  use JaguaWeb.ConnCase, async: true

  import Jagua.Factory

  describe "GET /in/:token" do
    test "returns 200 for valid token", %{conn: conn} do
      sentinel = create_sentinel()
      conn = get(conn, ~p"/in/#{sentinel.token}")
      assert text_response(conn, 200) =~ "Got it"
    end

    test "returns 404 for unknown token", %{conn: conn} do
      conn = get(conn, ~p"/in/doesnotexist")
      assert text_response(conn, 404) =~ "not found"
    end

    test "accepts optional message param", %{conn: conn} do
      sentinel = create_sentinel()
      conn = get(conn, ~p"/in/#{sentinel.token}?m=completed+ok")
      assert text_response(conn, 200) =~ "Got it"
    end

    test "accepts optional exit code param", %{conn: conn} do
      sentinel = create_sentinel()
      conn = get(conn, ~p"/in/#{sentinel.token}?s=0")
      assert text_response(conn, 200) =~ "Got it"
    end

    test "non-zero exit code marks sentinel as errored", %{conn: conn} do
      sentinel = create_sentinel()
      get(conn, ~p"/in/#{sentinel.token}?s=1")

      updated = Ash.get!(Jagua.Sentinels.Sentinel, sentinel.id, domain: Jagua.Sentinels)
      assert updated.status == :errored
    end

    test "zero exit code marks sentinel as healthy", %{conn: conn} do
      sentinel = create_sentinel()
      get(conn, ~p"/in/#{sentinel.token}?s=0")

      updated = Ash.get!(Jagua.Sentinels.Sentinel, sentinel.id, domain: Jagua.Sentinels)
      assert updated.status == :healthy
    end

    test "paused sentinel returns 200 without changing status", %{conn: conn} do
      sentinel = create_sentinel()

      sentinel
      |> Ash.Changeset.for_update(:pause, %{})
      |> Ash.update!(domain: Jagua.Sentinels)

      conn = get(conn, ~p"/in/#{sentinel.token}")
      assert text_response(conn, 200) =~ "paused"

      updated = Ash.get!(Jagua.Sentinels.Sentinel, sentinel.id, domain: Jagua.Sentinels)
      assert updated.status == :paused
    end

    test "records a check-in row", %{conn: conn} do
      sentinel = create_sentinel()
      get(conn, ~p"/in/#{sentinel.token}?m=hello&s=0")

      require Ash.Query

      check_ins =
        Jagua.Sentinels.CheckIn
        |> Ash.Query.for_read(:for_sentinel, %{sentinel_id: sentinel.id})
        |> Ash.read!(domain: Jagua.Sentinels)

      assert length(check_ins) == 1
      assert hd(check_ins).message == "hello"
      assert hd(check_ins).exit_code == 0
    end
  end

  describe "POST /in/:token" do
    test "also accepts POST", %{conn: conn} do
      sentinel = create_sentinel()
      conn = post(conn, ~p"/in/#{sentinel.token}")
      assert text_response(conn, 200) =~ "Got it"
    end
  end
end
