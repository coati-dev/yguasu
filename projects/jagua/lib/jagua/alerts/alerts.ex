defmodule Jagua.Alerts do
  use Ash.Domain, otp_app: :jagua

  resources do
    resource Jagua.Alerts.AlertChannel
    resource Jagua.Alerts.AlertEvent
  end
end
