defmodule Jagua.Repo do
  use AshPostgres.Repo,
    otp_app: :jagua

  def min_pg_version do
    %Version{major: 14, minor: 0, patch: 0}
  end

  def installed_extensions do
    ["uuid-ossp", "citext", "ash-functions"]
  end
end
