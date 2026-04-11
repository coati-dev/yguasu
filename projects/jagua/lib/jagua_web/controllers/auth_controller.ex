defmodule JaguaWeb.AuthController do
  use JaguaWeb, :controller

  alias Jagua.Accounts.Auth
  alias JaguaWeb.UserAuth

  @doc "Confirms a magic link token and logs the user in."
  def confirm(conn, %{"token" => token}) do
    case Auth.confirm_magic_link(token) do
      {:ok, user} ->
        conn
        |> UserAuth.log_in_user(user)
        |> put_flash(:info, "Welcome back!")
        |> redirect(to: ~p"/dashboard")

      {:error, _} ->
        conn
        |> put_flash(:error, "This login link is invalid or has expired. Please request a new one.")
        |> redirect(to: ~p"/login")
    end
  end

  def logout(conn, _params) do
    conn
    |> UserAuth.log_out_user()
    |> put_flash(:info, "You have been logged out.")
    |> redirect(to: ~p"/login")
  end
end
