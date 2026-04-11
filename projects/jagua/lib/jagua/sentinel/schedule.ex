defmodule Jagua.Sentinel.Schedule do
  @moduledoc """
  Calculates the next UTC window boundary for a given sentinel interval.

  The alerting model mirrors Dead Man's Snitch:
  - Each interval defines a set of fixed UTC "check points"
  - At each check point, the system evaluates whether a check-in was received
    since the previous check point
  - "next_window_end/1" returns the next upcoming check point in UTC
  """

  @interval_minutes %{
    :"1_minute" => 1,
    :"2_minute" => 2,
    :"3_minute" => 3,
    :"5_minute" => 5,
    :"10_minute" => 10,
    :"15_minute" => 15,
    :"20_minute" => 20,
    :"30_minute" => 30,
    :hourly => 60,
    :"2_hour" => 120,
    :"3_hour" => 180,
    :"4_hour" => 240,
    :"6_hour" => 360,
    :"8_hour" => 480,
    :"12_hour" => 720
  }

  @calendar_seconds %{
    daily: 86_400,
    weekly: 7 * 86_400,
    monthly: 30 * 86_400
  }

  @doc """
  Returns the approximate number of seconds in one interval period.
  For calendar intervals (daily/weekly/monthly) returns a nominal value.
  """
  def interval_seconds(interval) do
    case Map.get(@interval_minutes, interval) do
      nil -> Map.get(@calendar_seconds, interval, 86_400)
      minutes -> minutes * 60
    end
  end

  @doc """
  Returns the next UTC window boundary for the given interval atom.
  For sub-day intervals, calculates the next multiple of the period from UTC midnight.
  For daily/weekly/monthly, calculates the next calendar boundary.
  """
  def next_window_end(interval) when is_atom(interval) do
    now = DateTime.utc_now()

    case Map.get(@interval_minutes, interval) do
      nil -> next_calendar_boundary(interval, now)
      minutes -> next_minute_boundary(minutes, now)
    end
  end

  defp next_minute_boundary(period_minutes, now) do
    total_minutes = now.hour * 60 + now.minute
    periods_elapsed = div(total_minutes, period_minutes)
    next_period_start_minutes = (periods_elapsed + 1) * period_minutes

    next_hour = div(next_period_start_minutes, 60)
    next_minute = rem(next_period_start_minutes, 60)

    base = %{now | second: 0, microsecond: {0, 0}}

    if next_hour >= 24 do
      # Rolls over to next day
      tomorrow = DateTime.add(base, 1, :day)
      %{tomorrow | hour: 0, minute: rem(next_minute, 60)}
    else
      %{base | hour: next_hour, minute: next_minute}
    end
  end

  defp next_calendar_boundary(:daily, now) do
    tomorrow = DateTime.add(now, 1, :day)
    %{tomorrow | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
  end

  defp next_calendar_boundary(:weekly, now) do
    # Next Monday at midnight UTC
    days_until_monday = rem(8 - Date.day_of_week(DateTime.to_date(now)), 7)
    days_until_monday = if days_until_monday == 0, do: 7, else: days_until_monday
    next_monday = DateTime.add(now, days_until_monday, :day)
    %{next_monday | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
  end

  defp next_calendar_boundary(:monthly, now) do
    # 1st of next month at midnight UTC
    {year, month} =
      if now.month == 12 do
        {now.year + 1, 1}
      else
        {now.year, now.month + 1}
      end

    {:ok, first_of_month} = Date.new(year, month, 1)
    {:ok, dt} = DateTime.new(first_of_month, ~T[00:00:00], "Etc/UTC")
    dt
  end
end
