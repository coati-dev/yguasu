defmodule Jagua.ApiKeys do
  use Ash.Domain, otp_app: :jagua

  resources do
    resource Jagua.ApiKeys.ApiKey
  end
end
