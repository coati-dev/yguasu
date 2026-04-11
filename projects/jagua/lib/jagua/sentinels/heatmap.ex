defmodule Jagua.Sentinels.Heatmap do
  @moduledoc """
  Builds heatmap data for a sentinel's activity view.

  Each cell represents one interval period. Status is determined by whether
  a check-in was received in that window and what exit code it reported.

  Cell statuses:
    :healthy  — check-in received, exit code 0
    :errored  — check-in received, non-zero exit code
    :missed   — no check-in received (sentinel existed and was not paused)
    :future   — period hasn't happened yet
    :unknown  — before sentinel was created (no expectation either way)
  """

  require Ash.Query

  # How many cells to display per interval type
  @display_counts %{
    :"1_minute" => 120,   # 2 hours
    :"2_minute" => 120,   # 4 hours
    :"3_minute" => 120,   # 6 hours
    :"5_minute" => 144,   # 12 hours
    :"10_minute" => 144,  # 1 day
    :"15_minute" => 192,  # 2 days
    :"20_minute" => 216,  # 3 days
    :"30_minute" => 168,  # 3.5 days
    :hourly => 168,       # 7 days
    :"2_hour" => 168,     # 14 days
    :"3_hour" => 168,     # 21 days
    :"4_hour" => 180,     # 30 days
    :"6_hour" => 180,     # 45 days
    :"8_hour" => 180,     # 60 days
    :"12_hour" => 180,    # 90 days
    :daily => 365,        # 1 year
    :weekly => 52,        # 1 year
    :monthly => 24        # 2 years
  }

  @interval_seconds %{
    :"1_minute" => 60,
    :"2_minute" => 120,
    :"3_minute" => 180,
    :"5_minute" => 300,
    :"10_minute" => 600,
    :"15_minute" => 900,
    :"20_minute" => 1200,
    :"30_minute" => 1800,
    :hourly => 3600,
    :"2_hour" => 7200,
    :"3_hour" => 10800,
    :"4_hour" => 14400,
    :"6_hour" => 21600,
    :"8_hour" => 28800,
    :"12_hour" => 43200
  }

  @doc """
  Returns a list of cells for the heatmap, ordered oldest → newest.
  Each cell: %{bucket_start: DateTime, status: atom, count: integer}
  """
  def build(sentinel) do
    count = Map.get(@display_counts, sentinel.interval, 100)
    now = DateTime.utc_now()

    buckets = generate_buckets(sentinel.interval, count, now)

    since = List.first(buckets)
    check_ins = load_check_ins(sentinel.id, since)

    # Group check-ins by which bucket they fell into
    grouped =
      Enum.group_by(check_ins, fn ci ->
        bucket_for(ci.inserted_at, sentinel.interval)
      end)

    cells =
      Enum.map(buckets, fn bucket_start ->
        bucket_end = next_bucket(bucket_start, sentinel.interval)
        cis = Map.get(grouped, bucket_start, [])

        status =
          cond do
            DateTime.compare(bucket_start, now) == :gt ->
              :future

            DateTime.compare(bucket_start, sentinel.inserted_at) == :lt ->
              :unknown

            cis == [] ->
              :missed

            Enum.any?(cis, &(&1.exit_code != 0)) ->
              :errored

            true ->
              :healthy
          end

        %{
          bucket_start: bucket_start,
          bucket_end: bucket_end,
          status: status,
          count: length(cis)
        }
      end)

    %{
      cells: cells,
      interval: sentinel.interval,
      count: count
    }
  end

  # Generate the last `count` bucket start times, oldest first
  defp generate_buckets(interval, count, now) do
    current_bucket = bucket_for(now, interval)

    0..(count - 1)
    |> Enum.map(fn i -> subtract_buckets(current_bucket, interval, i) end)
    |> Enum.reverse()
  end

  # Subtract n buckets from a bucket start
  defp subtract_buckets(bucket, _interval, 0), do: bucket

  defp subtract_buckets(bucket, interval, n) when interval in [:daily, :weekly, :monthly] do
    prev = prev_calendar_bucket(bucket, interval)
    subtract_buckets(prev, interval, n - 1)
  end

  defp subtract_buckets(bucket, interval, n) do
    seconds = Map.fetch!(@interval_seconds, interval)
    DateTime.add(bucket, -n * seconds, :second)
  end

  # Find which bucket a given datetime belongs to
  def bucket_for(dt, interval) when interval in [:daily, :weekly, :monthly] do
    calendar_bucket(dt, interval)
  end

  def bucket_for(dt, interval) do
    seconds = Map.fetch!(@interval_seconds, interval)
    epoch = DateTime.to_unix(dt)
    bucket_epoch = div(epoch, seconds) * seconds
    DateTime.from_unix!(bucket_epoch)
  end

  defp calendar_bucket(dt, :daily) do
    {:ok, result} = DateTime.new(DateTime.to_date(dt), ~T[00:00:00], "Etc/UTC")
    result
  end

  defp calendar_bucket(dt, :weekly) do
    date = DateTime.to_date(dt)
    days_since_monday = Date.day_of_week(date) - 1
    monday = Date.add(date, -days_since_monday)
    {:ok, result} = DateTime.new(monday, ~T[00:00:00], "Etc/UTC")
    result
  end

  defp calendar_bucket(dt, :monthly) do
    {:ok, first} = Date.new(dt.year, dt.month, 1)
    {:ok, result} = DateTime.new(first, ~T[00:00:00], "Etc/UTC")
    result
  end

  defp next_bucket(bucket_start, interval) when interval in [:daily, :weekly, :monthly] do
    subtract_buckets(bucket_start, interval, -1)
  rescue
    _ -> DateTime.add(bucket_start, 86400, :second)
  end


  defp next_bucket(bucket_start, interval) do
    seconds = Map.fetch!(@interval_seconds, interval)
    DateTime.add(bucket_start, seconds, :second)
  end

  defp prev_calendar_bucket(bucket, :daily) do
    date = DateTime.to_date(bucket)
    prev = Date.add(date, -1)
    {:ok, result} = DateTime.new(prev, ~T[00:00:00], "Etc/UTC")
    result
  end

  defp prev_calendar_bucket(bucket, :weekly) do
    date = DateTime.to_date(bucket)
    prev = Date.add(date, -7)
    {:ok, result} = DateTime.new(prev, ~T[00:00:00], "Etc/UTC")
    result
  end

  defp prev_calendar_bucket(bucket, :monthly) do
    date = DateTime.to_date(bucket)
    prev =
      if date.month == 1 do
        {:ok, d} = Date.new(date.year - 1, 12, 1)
        d
      else
        {:ok, d} = Date.new(date.year, date.month - 1, 1)
        d
      end
    {:ok, result} = DateTime.new(prev, ~T[00:00:00], "Etc/UTC")
    result
  end

  defp load_check_ins(sentinel_id, since) do
    Jagua.Sentinels.CheckIn
    |> Ash.Query.for_read(:for_sentinel, %{sentinel_id: sentinel_id})
    |> Ash.Query.filter(inserted_at >= ^since)
    |> Ash.read!(domain: Jagua.Sentinels)
  end
end
