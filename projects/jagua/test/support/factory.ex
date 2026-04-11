defmodule Jagua.Factory do
  @moduledoc "Test factory helpers for building Ash records."

  def create_user(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})
    email = Map.get(attrs, :email, "user_#{System.unique_integer([:positive])}@example.com")

    Jagua.Accounts.User
    |> Ash.Changeset.for_create(:create, %{email: email})
    |> Ash.create!(domain: Jagua.Accounts)
  end

  def create_project(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})
    owner = Map.get_lazy(attrs, :owner, &create_user/0)
    name = Map.get(attrs, :name, "Project #{System.unique_integer([:positive])}")
    slug = Map.get(attrs, :slug, "project-#{System.unique_integer([:positive])}")

    Jagua.Projects.Project
    |> Ash.Changeset.for_create(:create, %{name: name, slug: slug, owner_id: owner.id})
    |> Ash.create!(domain: Jagua.Projects)
  end

  def create_sentinel(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})
    project = Map.get_lazy(attrs, :project, &create_project/0)
    name = Map.get(attrs, :name, "Sentinel #{System.unique_integer([:positive])}")
    interval = Map.get(attrs, :interval, :hourly)
    alert_type = Map.get(attrs, :alert_type, :basic)

    Jagua.Sentinels.Sentinel
    |> Ash.Changeset.for_create(:create, %{
      name: name,
      interval: interval,
      alert_type: alert_type,
      project_id: project.id
    })
    |> Ash.create!(domain: Jagua.Sentinels)
  end

  def create_check_in(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})
    sentinel = Map.get_lazy(attrs, :sentinel, &create_sentinel/0)
    exit_code = Map.get(attrs, :exit_code, 0)
    message = Map.get(attrs, :message, nil)

    Jagua.Sentinels.CheckIn
    |> Ash.Changeset.for_create(:record, %{
      sentinel_id: sentinel.id,
      exit_code: exit_code,
      message: message
    })
    |> Ash.create!(domain: Jagua.Sentinels)
  end

  def create_api_key(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})
    project = Map.get_lazy(attrs, :project, &create_project/0)
    name = Map.get(attrs, :name, "Test key")
    raw_key = "jg_testkey#{System.unique_integer([:positive])}"
    prefix = String.slice(raw_key, 0, 12)
    key_hash = :crypto.hash(:sha256, raw_key) |> Base.encode16(case: :lower)

    key =
      Jagua.ApiKeys.ApiKey
      |> Ash.Changeset.for_create(:create, %{
        name: name,
        project_id: project.id,
        prefix: prefix,
        key_hash: key_hash
      })
      |> Ash.create!(domain: Jagua.ApiKeys)

    {key, raw_key}
  end
end
