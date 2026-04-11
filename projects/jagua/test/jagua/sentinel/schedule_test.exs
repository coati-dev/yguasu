defmodule Jagua.Sentinel.ScheduleTest do
  use ExUnit.Case, async: true

  alias Jagua.Sentinel.Schedule

  describe "next_window_end/1" do
    test "returns a future datetime for all intervals" do
      intervals = [
        :"1_minute", :"5_minute", :"10_minute", :"15_minute", :"30_minute",
        :hourly, :"2_hour", :"6_hour", :"12_hour",
        :daily, :weekly, :monthly
      ]

      now = DateTime.utc_now()

      for interval <- intervals do
        result = Schedule.next_window_end(interval)
        assert DateTime.compare(result, now) == :gt,
               "Expected #{interval} next_window_end to be in the future, got #{result}"
      end
    end

    test "hourly result is at a whole clock hour" do
      result = Schedule.next_window_end(:hourly)
      assert result.minute == 0
      assert result.second == 0
    end

    test "30-minute result is at :00 or :30" do
      result = Schedule.next_window_end(:"30_minute")
      assert result.minute in [0, 30]
      assert result.second == 0
    end

    test "daily result is at midnight UTC" do
      result = Schedule.next_window_end(:daily)
      assert result.hour == 0
      assert result.minute == 0
      assert result.second == 0
    end

    test "weekly result is on a Monday" do
      result = Schedule.next_window_end(:weekly)
      assert Date.day_of_week(DateTime.to_date(result)) == 1
    end

    test "monthly result is on the 1st" do
      result = Schedule.next_window_end(:monthly)
      assert DateTime.to_date(result).day == 1
    end
  end

  describe "interval_seconds/1" do
    test "returns correct value for known intervals" do
      assert Schedule.interval_seconds(:"1_minute") == 60
      assert Schedule.interval_seconds(:hourly) == 3600
      assert Schedule.interval_seconds(:"12_hour") == 43200
      assert Schedule.interval_seconds(:daily) == 86_400
    end
  end
end
