defmodule JaguaWeb.Plugs.RateLimit do
  @moduledoc """
  Rate limiting plug using Jagua.RateLimiter.

  Usage in router:
    plug JaguaWeb.Plugs.RateLimit, type: :check_in, limit: 60, window: 60
    plug JaguaWeb.Plugs.RateLimit, type: :api, limit: 600, window: 60

  The key is derived from the conn — for check-in it uses the token path param,
  for API it uses the current_api_key id (set by ApiAuth plug).
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    type = Keyword.fetch!(opts, :type)
    limit = Keyword.fetch!(opts, :limit)
    window = Keyword.get(opts, :window, 60)

    key = rate_limit_key(conn, type)

    case Jagua.RateLimiter.check(type, key, limit, window) do
      :ok ->
        conn

      {:error, :rate_limited} ->
        conn
        |> put_resp_content_type("text/plain")
        |> put_resp_header("retry-after", to_string(window))
        |> send_resp(429, "Too many requests. Please slow down.")
        |> halt()
    end
  end

  defp rate_limit_key(conn, :check_in) do
    conn.path_params["token"] || conn.params["token"] || "unknown"
  end

  defp rate_limit_key(conn, :api) do
    case conn.assigns[:current_api_key] do
      nil -> Plug.Conn.get_peer_data(conn).address |> :inet.ntoa() |> to_string()
      key -> to_string(key.id)
    end
  end

  defp rate_limit_key(conn, _type) do
    Plug.Conn.get_peer_data(conn).address |> :inet.ntoa() |> to_string()
  end
end
