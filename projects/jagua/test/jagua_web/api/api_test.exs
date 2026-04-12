defmodule JaguaWeb.Api.ApiTest do
  # async: false — ApiAuth, CheckInController, and Dispatcher spawn Task.start tasks that do
  # DB work. Sandbox.allow/3 is called in each task so they inherit the test connection,
  # but allow/3 is a no-op in :shared mode, so async: false (shared: true) is still required
  # to give all spawned processes access to the same sandbox connection.
  use JaguaWeb.ConnCase, async: false

  import Jagua.Factory

  defp auth_conn(conn, raw_key) do
    put_req_header(conn, "authorization", "Bearer #{raw_key}")
  end

  describe "authentication" do
    test "returns 401 without Authorization header", %{conn: conn} do
      conn = get(conn, ~p"/api/projects")
      assert json_response(conn, 401)["error"] == "unauthorized"
    end

    test "returns 401 with invalid key", %{conn: conn} do
      conn =
        conn
        |> auth_conn("jg_notarealkey")
        |> get(~p"/api/projects")

      assert json_response(conn, 401)["error"] == "unauthorized"
    end

    test "returns 200 with valid key", %{conn: conn} do
      {_key, raw_key} = create_api_key()

      conn =
        conn
        |> auth_conn(raw_key)
        |> get(~p"/api/projects")

      assert json_response(conn, 200)
    end
  end

  describe "GET /api/projects" do
    test "returns the project scoped to the API key", %{conn: conn} do
      {key, raw_key} = create_api_key()
      project = Ash.get!(Jagua.Projects.Project, key.project_id, domain: Jagua.Projects)

      resp =
        conn
        |> auth_conn(raw_key)
        |> get(~p"/api/projects")
        |> json_response(200)

      assert length(resp) == 1
      assert hd(resp)["id"] == to_string(project.id)
      assert hd(resp)["name"] == project.name
    end
  end

  describe "GET /api/projects/:id" do
    test "returns the project", %{conn: conn} do
      {key, raw_key} = create_api_key()
      project = Ash.get!(Jagua.Projects.Project, key.project_id, domain: Jagua.Projects)

      resp =
        conn
        |> auth_conn(raw_key)
        |> get(~p"/api/projects/#{project.id}")
        |> json_response(200)

      assert resp["id"] == to_string(project.id)
    end

    test "returns 404 for a different project", %{conn: conn} do
      {_key, raw_key} = create_api_key()
      other_project = create_project()

      conn
      |> auth_conn(raw_key)
      |> get(~p"/api/projects/#{other_project.id}")
      |> json_response(404)
    end
  end

  describe "sentinel CRUD" do
    setup %{conn: conn} do
      {key, raw_key} = create_api_key()
      project = Ash.get!(Jagua.Projects.Project, key.project_id, domain: Jagua.Projects)
      {:ok, conn: auth_conn(conn, raw_key), project: project}
    end

    test "POST creates a sentinel", %{conn: conn, project: project} do
      resp =
        conn
        |> post(~p"/api/projects/#{project.id}/sentinels", %{
          name: "My job",
          interval: "hourly"
        })
        |> json_response(201)

      assert resp["name"] == "My job"
      assert resp["interval"] == "hourly"
      assert resp["status"] == "pending"
      assert resp["token"] != nil
    end

    test "GET index returns sentinels", %{conn: conn, project: project} do
      create_sentinel(project: project, name: "Alpha")
      create_sentinel(project: project, name: "Beta")

      resp =
        conn
        |> get(~p"/api/projects/#{project.id}/sentinels")
        |> json_response(200)

      assert length(resp) == 2
    end

    test "GET show returns a sentinel by token", %{conn: conn, project: project} do
      sentinel = create_sentinel(project: project)

      resp =
        conn
        |> get(~p"/api/projects/#{project.id}/sentinels/#{sentinel.token}")
        |> json_response(200)

      assert resp["token"] == sentinel.token
    end

    test "PATCH updates a sentinel", %{conn: conn, project: project} do
      sentinel = create_sentinel(project: project)

      resp =
        conn
        |> patch(~p"/api/projects/#{project.id}/sentinels/#{sentinel.token}", %{
          name: "Updated name"
        })
        |> json_response(200)

      assert resp["name"] == "Updated name"
    end

    test "DELETE removes a sentinel", %{conn: conn, project: project} do
      sentinel = create_sentinel(project: project)

      conn
      |> delete(~p"/api/projects/#{project.id}/sentinels/#{sentinel.token}")
      |> response(204)

      assert {:ok, nil} ==
               Ash.read_one(
                 Ash.Query.for_read(
                   Jagua.Sentinels.Sentinel,
                   :by_token,
                   %{token: sentinel.token}
                 ),
                 domain: Jagua.Sentinels
               )
    end

    test "pause changes sentinel status", %{conn: conn, project: project} do
      sentinel = create_sentinel(project: project)

      resp =
        conn
        |> post(~p"/api/projects/#{project.id}/sentinels/#{sentinel.token}/pause")
        |> json_response(200)

      assert resp["status"] == "paused"
    end

    test "unpause changes sentinel status back to pending", %{conn: conn, project: project} do
      sentinel = create_sentinel(project: project)

      sentinel
      |> Ash.Changeset.for_update(:pause, %{})
      |> Ash.update!(domain: Jagua.Sentinels)

      resp =
        conn
        |> post(~p"/api/projects/#{project.id}/sentinels/#{sentinel.token}/unpause")
        |> json_response(200)

      assert resp["status"] == "pending"
    end
  end

  describe "GET check_ins" do
    test "returns check-in history", %{conn: conn} do
      {key, raw_key} = create_api_key()
      project = Ash.get!(Jagua.Projects.Project, key.project_id, domain: Jagua.Projects)
      sentinel = create_sentinel(project: project)
      create_check_in(sentinel: sentinel, exit_code: 0)
      create_check_in(sentinel: sentinel, exit_code: 1)

      resp =
        conn
        |> auth_conn(raw_key)
        |> get(~p"/api/projects/#{project.id}/sentinels/#{sentinel.token}/check_ins")
        |> json_response(200)

      assert length(resp) == 2
    end
  end
end
