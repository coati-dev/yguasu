defmodule Jagua.Accounts do
  use Ash.Domain, otp_app: :jagua

  resources do
    resource Jagua.Accounts.User
    resource Jagua.Accounts.MagicLink
    resource Jagua.Accounts.PasskeyCredential
  end
end
