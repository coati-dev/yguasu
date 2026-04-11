defmodule Jagua.Projects do
  use Ash.Domain, otp_app: :jagua

  resources do
    resource Jagua.Projects.Project
    resource Jagua.Projects.Membership
  end
end
