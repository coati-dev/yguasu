defmodule JaguaWeb.Api.SentinelController do
  use JaguaWeb, :controller

  require Ash.Query

  @doc "GET /api/projects/:project_id/sentinels"
  def index(conn, %{"project_id" => project_id}) do
    with :ok <- check_project(conn, project_id) do
      sentinels =
        Jagua.Sentinels.Sentinel
        |> Ash.Query.for_read(:for_project, %{project_id: conn.assigns.current_project.id})
        |> Ash.read!(domain: Jagua.Sentinels)

      json(conn, Enum.map(sentinels, &render_sentinel/1))
    end
  end

  @doc "POST /api/projects/:project_id/sentinels"
  def create(conn, %{"project_id" => project_id} = params) do
    with :ok <- check_project(conn, project_id) do
      attrs =
        params
        |> Map.take(["name", "interval", "alert_type", "notes", "tags"])
        |> Map.put("project_id", conn.assigns.current_project.id)
        |> atomize()

      case Jagua.Sentinels.Sentinel
           |> Ash.Changeset.for_create(:create, attrs)
           |> Ash.create(domain: Jagua.Sentinels) do
        {:ok, sentinel} ->
          Jagua.Sentinel.Timer.ensure_started(sentinel)
          conn |> put_status(201) |> json(render_sentinel(sentinel))

        {:error, changeset} ->
          conn |> put_status(422) |> json(errors(changeset))
      end
    end
  end

  @doc "GET /api/projects/:project_id/sentinels/:token"
  def show(conn, %{"project_id" => project_id, "token" => token}) do
    with :ok <- check_project(conn, project_id),
         {:ok, sentinel} <- load_sentinel(token, conn.assigns.current_project.id) do
      json(conn, render_sentinel(sentinel))
    end
  end

  @doc "PATCH /api/projects/:project_id/sentinels/:token"
  def update(conn, %{"project_id" => project_id, "token" => token} = params) do
    with :ok <- check_project(conn, project_id),
         {:ok, sentinel} <- load_sentinel(token, conn.assigns.current_project.id) do
      attrs =
        params
        |> Map.take(["name", "interval", "alert_type", "notes", "tags"])
        |> atomize()

      case sentinel
           |> Ash.Changeset.for_update(:update, attrs)
           |> Ash.update(domain: Jagua.Sentinels) do
        {:ok, updated} -> json(conn, render_sentinel(updated))
        {:error, changeset} -> conn |> put_status(422) |> json(errors(changeset))
      end
    end
  end

  @doc "DELETE /api/projects/:project_id/sentinels/:token"
  def delete(conn, %{"project_id" => project_id, "token" => token}) do
    with :ok <- check_project(conn, project_id),
         {:ok, sentinel} <- load_sentinel(token, conn.assigns.current_project.id) do
      Jagua.Sentinel.Timer.stop(sentinel.id)
      Ash.destroy!(sentinel, domain: Jagua.Sentinels)
      send_resp(conn, 204, "")
    end
  end

  @doc "POST /api/projects/:project_id/sentinels/:sentinel_token/pause"
  def pause(conn, %{"project_id" => project_id, "sentinel_token" => token}) do
    with :ok <- check_project(conn, project_id),
         {:ok, sentinel} <- load_sentinel(token, conn.assigns.current_project.id) do
      updated =
        sentinel
        |> Ash.Changeset.for_update(:pause, %{})
        |> Ash.update!(domain: Jagua.Sentinels)

      Jagua.Sentinel.Timer.stop(sentinel.id)
      json(conn, render_sentinel(updated))
    end
  end

  @doc "POST /api/projects/:project_id/sentinels/:sentinel_token/unpause"
  def unpause(conn, %{"project_id" => project_id, "sentinel_token" => token}) do
    with :ok <- check_project(conn, project_id),
         {:ok, sentinel} <- load_sentinel(token, conn.assigns.current_project.id) do
      updated =
        sentinel
        |> Ash.Changeset.for_update(:unpause, %{})
        |> Ash.update!(domain: Jagua.Sentinels)

      Jagua.Sentinel.Timer.ensure_started(updated)
      json(conn, render_sentinel(updated))
    end
  end

  defp load_sentinel(token, project_id) do
    query =
      Jagua.Sentinels.Sentinel
      |> Ash.Query.for_read(:by_token, %{token: token})

    case Ash.read_one(query, domain: Jagua.Sentinels) do
      {:ok, nil} -> not_found_halt(nil)
      {:ok, sentinel} when sentinel.project_id == project_id -> {:ok, sentinel}
      _ -> not_found_halt(nil)
    end
  end

  defp check_project(conn, project_id) do
    if to_string(conn.assigns.current_project.id) == project_id do
      :ok
    else
      not_found_halt(conn)
    end
  end

  defp not_found_halt(nil), do: {:error, :not_found}

  defp not_found_halt(conn) do
    conn |> put_status(404) |> json(%{error: "not found"}) |> halt()
    {:error, :not_found}
  end

  defp render_sentinel(s) do
    %{
      id: s.id,
      token: s.token,
      name: s.name,
      interval: s.interval,
      status: s.status,
      alert_type: s.alert_type,
      notes: s.notes,
      tags: s.tags,
      last_check_in_at: s.last_check_in_at,
      inserted_at: s.inserted_at
    }
  end

  defp atomize(map) do
    Map.new(map, fn {k, v} -> {String.to_existing_atom(k), v} end)
  end

  defp errors(changeset) do
    %{errors: Ash.Error.to_error_class(changeset).errors |> Enum.map(& &1.message)}
  rescue
    _ -> %{errors: ["invalid"]}
  end
end
