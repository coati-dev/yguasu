defmodule JaguaWeb.Plugs.ApiAuth do
  @moduledoc """
  Authenticates REST API requests via Bearer token.

  Reads Authorization: Bearer <key>, hashes it with SHA-256, and looks up
  the matching ApiKey. Assigns :current_api_key and :current_project to the
  conn, or halts with 401 if the key is invalid.

  Also touches last_used_at asynchronously so it doesn't add latency.
  """

  import Plug.Conn

  require Ash.Query

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> raw_key] <- get_req_header(conn, "authorization"),
         key_hash = hash(raw_key),
         {:ok, [api_key | _]} <- load_key(key_hash),
         {:ok, project} <- load_project(api_key.project_id) do
      caller = self()
      Task.start(fn ->
        try do
          Ecto.Adapters.SQL.Sandbox.allow(Jagua.Repo, caller, self())
          touch_key(api_key)
        catch
          :exit, _ -> :ok
        end
      end)

      conn
      |> assign(:current_api_key, api_key)
      |> assign(:current_project, project)
    else
      _ -> unauthorized(conn)
    end
  end

  defp load_key(key_hash) do
    result =
      Jagua.ApiKeys.ApiKey
      |> Ash.Query.for_read(:by_key_hash, %{key_hash: key_hash})
      |> Ash.read(domain: Jagua.ApiKeys)

    case result do
      {:ok, [_ | _] = keys} -> {:ok, keys}
      _ -> :error
    end
  end

  defp load_project(project_id) do
    case Ash.get(Jagua.Projects.Project, project_id, domain: Jagua.Projects) do
      {:ok, project} when not is_nil(project) -> {:ok, project}
      _ -> :error
    end
  end

  defp touch_key(api_key) do
    api_key
    |> Ash.Changeset.for_update(:touch, %{})
    |> Ash.update(domain: Jagua.ApiKeys)
  end

  defp hash(raw_key) do
    :crypto.hash(:sha256, raw_key) |> Base.encode16(case: :lower)
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, ~s({"error":"unauthorized"}))
    |> halt()
  end
end
