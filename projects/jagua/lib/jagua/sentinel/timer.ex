defmodule Jagua.Sentinel.Timer do
  @moduledoc """
  One GenServer per active sentinel. Responsible for:
  - Tracking the next expected check-in window boundary
  - Marking the sentinel as failed if no check-in is received by deadline
  - Implementing smart alerts (early fire based on historical timing µ + 2σ)
  - Sending pending and paused reminders after 3 days

  Process is registered under {:via, Registry, {Jagua.Sentinel.Registry, sentinel_id}}.
  """

  use GenServer, restart: :transient

  require Logger
  require Ash.Query

  alias Jagua.Sentinels
  alias Jagua.Sentinel.Schedule

  @min_smart_samples 5
  # 3 days in seconds
  @reminder_threshold_seconds 3 * 24 * 60 * 60

  defstruct [
    :sentinel_id,
    :interval,
    :alert_type,
    :status,
    :created_at,
    :paused_at,
    :next_check_time,
    :check_in_received?,
    :timer_ref,
    :smart_timer_ref,
    :reminder_timer_ref
  ]

  # Public API

  def start_link(%{id: id} = sentinel) do
    GenServer.start_link(__MODULE__, sentinel, name: via(id))
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
  def init(%{id: id, interval: interval, alert_type: alert_type, status: status,
             inserted_at: inserted_at, paused_at: paused_at}) do
    state = %__MODULE__{
      sentinel_id: id,
      interval: interval,
      alert_type: alert_type,
      status: status,
      created_at: inserted_at,
      paused_at: paused_at,
      check_in_received?: false,
      timer_ref: nil,
      smart_timer_ref: nil,
      reminder_timer_ref: nil
    }

    state = schedule_next(state)
    state = maybe_schedule_smart_alert(state)
    state = schedule_reminder(state)

    {:ok, state}
  end

  @impl true
  def handle_cast(:check_in, state) do
    # Cancel smart timer if it hasn't fired yet
    if state.smart_timer_ref, do: Process.cancel_timer(state.smart_timer_ref)

    {:noreply, %{state | check_in_received?: true, smart_timer_ref: nil}}
  end

  @impl true
  def handle_info(:check_window, state) do
    if state.check_in_received? do
      state = schedule_next(%{state | check_in_received?: false})
      state = maybe_schedule_smart_alert(state)
      {:noreply, state}
    else
      fire_alert(state.sentinel_id, :failed)
      state = schedule_next(%{state | check_in_received?: false})
      state = maybe_schedule_smart_alert(state)
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:smart_check, state) do
    unless state.check_in_received? do
      Logger.info("Sentinel #{state.sentinel_id} smart alert triggered — firing early alert")
      fire_alert(state.sentinel_id, :failed)
    end

    {:noreply, %{state | smart_timer_ref: nil}}
  end

  @impl true
  def handle_info(:send_reminder, state) do
    sentinel =
      Ash.get!(Jagua.Sentinels.Sentinel, state.sentinel_id, domain: Sentinels)

    cond do
      sentinel.status == :pending ->
        Jagua.Alerts.Dispatcher.dispatch(sentinel, :pending_reminder)

      sentinel.status == :paused ->
        Jagua.Alerts.Dispatcher.dispatch(sentinel, :paused_reminder)

      true ->
        :noop
    end

    {:noreply, %{state | reminder_timer_ref: nil}}
  rescue
    e ->
      Logger.error("Reminder check failed for sentinel #{state.sentinel_id}: #{inspect(e)}")
      {:noreply, %{state | reminder_timer_ref: nil}}
  end

  # Private

  defp schedule_next(%{interval: interval} = state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    next_check_time = Schedule.next_window_end(interval)
    delay_ms = DateTime.diff(next_check_time, DateTime.utc_now(), :millisecond)
    delay_ms = max(delay_ms, 1_000)

    timer_ref = Process.send_after(self(), :check_window, delay_ms)
    %{state | next_check_time: next_check_time, timer_ref: timer_ref}
  end

  defp maybe_schedule_smart_alert(%{alert_type: :basic} = state), do: state

  defp maybe_schedule_smart_alert(%{alert_type: :smart} = state) do
    if state.smart_timer_ref, do: Process.cancel_timer(state.smart_timer_ref)

    case compute_smart_fire_offset(state.sentinel_id, state.interval) do
      {:ok, offset_seconds} ->
        # Find the start of the current window
        window_end = state.next_check_time
        window_seconds = Schedule.interval_seconds(state.interval)
        window_start = DateTime.add(window_end, -window_seconds, :second)

        fire_at = DateTime.add(window_start, trunc(offset_seconds), :second)
        delay_ms = DateTime.diff(fire_at, DateTime.utc_now(), :millisecond)

        if delay_ms > 0 do
          Logger.debug("Smart alert for #{state.sentinel_id} in #{delay_ms}ms (offset #{offset_seconds}s)")
          ref = Process.send_after(self(), :smart_check, delay_ms)
          %{state | smart_timer_ref: ref}
        else
          # The smart fire time has already passed in this window; fall through to basic
          %{state | smart_timer_ref: nil}
        end

      :insufficient_data ->
        %{state | smart_timer_ref: nil}
    end
  end

  defp compute_smart_fire_offset(sentinel_id, interval) do
    window_seconds = Schedule.interval_seconds(interval)

    check_ins =
      Jagua.Sentinels.CheckIn
      |> Ash.Query.for_read(:recent_for_sentinel, %{sentinel_id: sentinel_id, limit: 50})
      |> Ash.read!(domain: Sentinels)

    if length(check_ins) < @min_smart_samples do
      :insufficient_data
    else
      offsets =
        Enum.map(check_ins, fn ci ->
          epoch = DateTime.to_unix(ci.inserted_at)
          rem(epoch, window_seconds)
        end)

      n = length(offsets)
      mean = Enum.sum(offsets) / n
      variance = Enum.sum(Enum.map(offsets, fn x -> (x - mean) ** 2 end)) / n
      std_dev = :math.sqrt(variance)

      # Fire at µ + 2σ, capped at 90% of the window
      fire_at = min(mean + 2 * std_dev, window_seconds * 0.9)
      {:ok, fire_at}
    end
  end

  defp schedule_reminder(state) do
    if state.reminder_timer_ref, do: Process.cancel_timer(state.reminder_timer_ref)

    threshold_dt =
      case state.status do
        :pending ->
          DateTime.add(state.created_at, @reminder_threshold_seconds, :second)

        :paused when not is_nil(state.paused_at) ->
          DateTime.add(state.paused_at, @reminder_threshold_seconds, :second)

        _ ->
          nil
      end

    case threshold_dt do
      nil ->
        %{state | reminder_timer_ref: nil}

      dt ->
        delay_ms = DateTime.diff(dt, DateTime.utc_now(), :millisecond)

        if delay_ms > 0 do
          ref = Process.send_after(self(), :send_reminder, delay_ms)
          %{state | reminder_timer_ref: ref}
        else
          # Threshold already passed — check immediately
          ref = Process.send_after(self(), :send_reminder, 0)
          %{state | reminder_timer_ref: ref}
        end
    end
  end

  defp fire_alert(sentinel_id, type) do
    Logger.warning("Sentinel #{sentinel_id} — firing #{type} alert")

    sentinel = Ash.get!(Jagua.Sentinels.Sentinel, sentinel_id, domain: Sentinels)

    sentinel
    |> Ash.Changeset.for_update(:mark_failed, %{})
    |> Ash.update!(domain: Sentinels)

    Jagua.Alerts.Dispatcher.dispatch(sentinel, type)
  rescue
    e ->
      Logger.error("Failed to fire alert for sentinel #{sentinel_id}: #{inspect(e)}")
  end

  defp via(sentinel_id) do
    {:via, Registry, {Jagua.Sentinel.Registry, sentinel_id}}
  end
end
