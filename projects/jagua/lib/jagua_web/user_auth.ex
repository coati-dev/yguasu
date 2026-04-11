defmodule JaguaWeb.UserAuth do
  @moduledoc """
  Session management and LiveView on_mount hooks for authentication.
  """

  import Plug.Conn
  import Phoenix.Controller

  use JaguaWeb, :verified_routes

  @session_key "user_id"

  # --- Plugs ---

  @doc "Loads current_user from session into conn.assigns."
  def fetch_current_user(conn, _opts) do
    user_id = get_session(conn, @session_key)

    user =
      if user_id do
        case Ash.get(Jagua.Accounts.User, user_id, domain: Jagua.Accounts) do
          {:ok, user} -> user
          _ -> nil
        end
      end

    assign(conn, :current_user, user)
  end

  @doc "Halts and redirects to /login if not authenticated."
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end

  @doc "Writes user_id into the session."
  def log_in_user(conn, user) do
    conn
    |> renew_session()
    |> put_session(@session_key, user.id)
    |> put_resp_cookie("_jagua_user", user.id,
      max_age: 60 * 60 * 24 * 60,
      same_site: "Lax",
      http_only: true
    )
  end

  @doc "Clears the session."
  def log_out_user(conn) do
    conn
    |> renew_session()
    |> delete_resp_cookie("_jagua_user")
  end

  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  # --- LiveView on_mount hooks ---
  # :fetch_current_user — assigns current_user (nil if not logged in)
  # :ensure_authenticated — redirects to /login if not logged in
  # :redirect_if_authenticated — redirects to /dashboard if already logged in

  def on_mount(:fetch_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/login")

      {:halt, socket}
    end
  end

  def on_mount(:redirect_if_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/dashboard")}
    else
      {:cont, socket}
    end
  end

  defp mount_current_user(socket, session) do
    user_id = session[@session_key]

    user =
      if user_id do
        case Ash.get(Jagua.Accounts.User, user_id, domain: Jagua.Accounts) do
          {:ok, user} -> user
          _ -> nil
        end
      end

    Phoenix.Component.assign(socket, :current_user, user)
  end
end
