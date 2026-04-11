defmodule JaguaWeb.SentinelHelpers do
  @moduledoc "Shared display helpers for sentinel LiveViews."

  def format_interval(interval) do
    case interval do
      :"1_minute" -> "1 minute"
      :"2_minute" -> "2 minutes"
      :"3_minute" -> "3 minutes"
      :"5_minute" -> "5 minutes"
      :"10_minute" -> "10 minutes"
      :"15_minute" -> "15 minutes"
      :"20_minute" -> "20 minutes"
      :"30_minute" -> "30 minutes"
      :hourly -> "Hourly"
      :"2_hour" -> "2 hours"
      :"3_hour" -> "3 hours"
      :"4_hour" -> "4 hours"
      :"6_hour" -> "6 hours"
      :"8_hour" -> "8 hours"
      :"12_hour" -> "12 hours"
      :daily -> "Daily"
      :weekly -> "Weekly"
      :monthly -> "Monthly"
    end
  end

  def format_ago(dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end
end
