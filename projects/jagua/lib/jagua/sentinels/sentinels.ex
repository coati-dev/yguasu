defmodule Jagua.Sentinels do
  use Ash.Domain, otp_app: :jagua

  resources do
    resource Jagua.Sentinels.Sentinel
    resource Jagua.Sentinels.CheckIn
  end
end
