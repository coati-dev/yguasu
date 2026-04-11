defmodule Jagua.Sentinel.Timer do
  @moduledoc """
  One GenServer per active sentinel. Responsible for:
  - Tracking the next expected check-in window boundary
  - Marking the sentinel as failed if no check-in is received by deadline
  - Implementing smart alerts (early fire based on historical timing)

  Process is registered under {:via, Registry, {Jagua.Sentinel.Registry, sentinel_id}}.
  """

  use GenServer, restart: :transient

  require Logger

  alias Jagua.Sentinels
  alias Jagua.Sentinel.Schedule

  defstruct [:sentinel_id, :interval, :alert_type, :next_check_time, :check_in_received?, :timer_ref]

  # Public API

  def start_link(%{id: id} = sentinel) do
    GenServer.start_link(__MODULE__, sentinel,
      name: via(id)
    )
  end

  def ensure_started(%{id: id, status: status} = sentinel) when status != :paused do
    case Registry.lookup(Jagua.Sentinel.Registry, id) do
      [] -> DynamicSupervisor.start_child(Jagua.Sentinel.Supervisor, {__MODULE__, sentinel})
      _ -> :already_running
    end
  end

  def ensure_started(_sentinel), do: :paused

  def stop(sentinel_id) do
    case Registry.lookup(Jagua.Sentinel.Registry, sentinel_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(Jagua.Sentinel.Supervisor, pid)
      [] -> :not_running
    end
  end

  def notify_check_in(sentinel_id) do
    case Registry.lookup(Jagua.Sentinel.Registry, sentinel_id) do
      [{pid, _}] -> GenServer.cast(pid, :check_in)
      [] -> :not_running
    end
  end

  # GenServer callbacks

  @impl true
  def init(%{id: id, interval: interval, alert_type: alert_type}) do
    state = %__MODULE__{
      sentinel_id: id,
      interval: interval,
      alert_type: alert_type,
      check_in_received?: false,
      timer_ref: nil
    }

    {:ok, schedule_next(state)}
  end

  @impl true
  def handle_cast(:check_in, state) do
    {:noreply, %{state | check_in_received?: true}}
  end

  @impl true
  def handle_info(:check_window, state) do
    if state.check_in_received? do
      # Window passed with a check-in — schedule next window
      {:noreply, schedule_next(%{state | check_in_received?: false})}
    else
      # No check-in received — mark as failed and alert
      fire_alert(state.sentinel_id)
      {:noreply, schedule_next(%{state | check_in_received?: false})}
    end
  end

  # Private

  defp schedule_next(%{interval: interval} = state) do
    next_check_time = Schedule.next_window_end(interval)
    delay_ms = DateTime.diff(next_check_time, DateTime.utc_now(), :millisecond)
    delay_ms = max(delay_ms, 1_000)

    timer_ref = Process.send_after(self(), :check_window, delay_ms)

    %{state | next_check_time: next_check_time, timer_ref: timer_ref}
  end

  defp fire_alert(sentinel_id) do
    Logger.warning("Sentinel #{sentinel_id} missed check-in — firing alert")

    sentinel =
      Jagua.Sentinels.Sentinel
      |> Ash.Query.for_read(:by_token, %{})
      |> then(fn _ ->
        Ash.get!(Jagua.Sentinels.Sentinel, sentinel_id, domain: Sentinels)
      end)

    sentinel
    |> Ash.Changeset.for_update(:mark_failed, %{})
    |> Ash.update!(domain: Sentinels)
    Jagua.Alerts.Dispatcher.dispatch(sentinel, :failed)
  rescue
    e ->
      Logger.error("Failed to fire alert for sentinel #{sentinel_id}: #{inspect(e)}")
  end

  defp via(sentinel_id) do
    {:via, Registry, {Jagua.Sentinel.Registry, sentinel_id}}
  end
end
