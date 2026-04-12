defmodule JaguaWeb.PageController do
  use JaguaWeb, :controller

  def home(conn, _params) do
    render(conn, :home, layout: false, current_user: conn.assigns[:current_user])
  end
end
