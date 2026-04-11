defmodule JaguaWeb.Api.CheckInController do
  use JaguaWeb, :controller

  require Ash.Query

  @doc "GET /api/projects/:project_id/sentinels/:token/check_ins"
  def index(conn, %{"project_id" => project_id, "sentinel_token" => token} = params) do
    if to_string(conn.assigns.current_project.id) == project_id do
      sentinel_query =
        Jagua.Sentinels.Sentinel
        |> Ash.Query.for_read(:by_token, %{token: token})

      case Ash.read_one(sentinel_query, domain: Jagua.Sentinels) do
        {:ok, sentinel} when not is_nil(sentinel) and sentinel.project_id == conn.assigns.current_project.id ->
          limit = min(String.to_integer(Map.get(params, "limit", "50")), 200)

          check_ins =
            Jagua.Sentinels.CheckIn
            |> Ash.Query.for_read(:recent_for_sentinel, %{
              sentinel_id: sentinel.id,
              limit: limit
            })
            |> Ash.read!(domain: Jagua.Sentinels)

          json(conn, Enum.map(check_ins, &render_check_in/1))

        _ ->
          conn |> put_status(404) |> json(%{error: "not found"})
      end
    else
      conn |> put_status(404) |> json(%{error: "not found"})
    end
  end

  defp render_check_in(ci) do
    %{
      id: ci.id,
      exit_code: ci.exit_code,
      status: ci.status,
      message: ci.message,
      inserted_at: ci.inserted_at
    }
  end
end
