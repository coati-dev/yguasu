defmodule JaguaWeb.Api.ProjectController do
  use JaguaWeb, :controller

  @doc "GET /api/projects — returns the single project scoped to the API key"
  def index(conn, _params) do
    json(conn, [render_project(conn.assigns.current_project)])
  end

  @doc "GET /api/projects/:id"
  def show(conn, %{"id" => id}) do
    project = conn.assigns.current_project

    if to_string(project.id) == id do
      json(conn, render_project(project))
    else
      conn |> put_status(404) |> json(%{error: "not found"})
    end
  end

  @doc "POST /api/projects — not supported at key scope; returns 405"
  def create(conn, _params) do
    conn |> put_status(405) |> json(%{error: "creating projects via API is not supported"})
  end

  @doc "PATCH /api/projects/:id"
  def update(conn, %{"id" => id} = params) do
    project = conn.assigns.current_project

    if to_string(project.id) == id do
      attrs = Map.take(params, ["name", "slug", "public_status_page"])

      case project
           |> Ash.Changeset.for_update(:update, atomize(attrs))
           |> Ash.update(domain: Jagua.Projects) do
        {:ok, updated} -> json(conn, render_project(updated))
        {:error, changeset} -> conn |> put_status(422) |> json(errors(changeset))
      end
    else
      conn |> put_status(404) |> json(%{error: "not found"})
    end
  end

  @doc "DELETE /api/projects/:id"
  def delete(conn, %{"id" => id}) do
    project = conn.assigns.current_project

    if to_string(project.id) == id do
      Ash.destroy!(project, domain: Jagua.Projects)
      send_resp(conn, 204, "")
    else
      conn |> put_status(404) |> json(%{error: "not found"})
    end
  end

  defp render_project(p) do
    %{
      id: p.id,
      name: p.name,
      slug: p.slug,
      public_status_page: p.public_status_page,
      inserted_at: p.inserted_at
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
