defmodule JaguaWeb.CheckInController do
  use JaguaWeb, :controller

  require Ash.Query

  @doc """
  Handles sentinel check-ins via GET or POST to /in/:token.

  Optional query/body params:
    - m: message (string)
    - s: exit code (integer, 0=healthy non-zero=errored)
  """
  def check_in(conn, %{"token" => token} = params) do
    message = params["m"]
    exit_code = parse_exit_code(params["s"])

    query =
      Jagua.Sentinels.Sentinel
      |> Ash.Query.for_read(:by_token, %{token: token})

    case Ash.read_one(query, domain: Jagua.Sentinels) do
      {:ok, nil} ->
        conn
        |> put_status(:not_found)
        |> text("Sentinel not found.")

      {:ok, sentinel} ->
        handle_check_in(conn, sentinel, exit_code, message)

      {:error, _} ->
        conn
        |> put_status(:internal_server_error)
        |> text("Something went wrong.")
    end
  end

  defp handle_check_in(conn, sentinel, _exit_code, _message)
       when sentinel.status == :paused do
    # Still accept the check-in but don't change status
    conn
    |> put_status(:ok)
    |> text("Jagua got it! Much obliged (sentinel is paused).")
  end

  defp handle_check_in(conn, sentinel, exit_code, message) do
    prev_status = sentinel.status

    # Record check-in in DB
    Jagua.Sentinels.CheckIn
    |> Ash.Changeset.for_create(:record, %{
      sentinel_id: sentinel.id,
      exit_code: exit_code,
      message: message
    })
    |> Ash.create!(domain: Jagua.Sentinels)

    # Update sentinel status
    updated =
      sentinel
      |> Ash.Changeset.for_update(:check_in, %{exit_code: exit_code, message: message})
      |> Ash.update!(domain: Jagua.Sentinels)

    # Fire recovered alert if it was previously failed/errored and is now healthy
    if prev_status in [:failed, :errored] and updated.status == :healthy do
      Jagua.Tasks.start(fn -> Jagua.Alerts.Dispatcher.dispatch(updated, :recovered) end)
    end

    # Notify the OTP timer so it resets the window
    Jagua.Sentinel.Timer.notify_check_in(sentinel.id)

    conn
    |> put_status(:ok)
    |> text("Jagua got it! Much obliged.")
  end

  defp parse_exit_code(nil), do: 0
  defp parse_exit_code(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> 0
    end
  end
  defp parse_exit_code(n) when is_integer(n), do: n
end
