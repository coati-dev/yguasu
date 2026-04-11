defmodule Jagua.ApiKeys.ApiKey do
  use Ash.Resource,
    domain: Jagua.ApiKeys,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "api_keys"
    repo Jagua.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true

    # First 8 chars of the raw key, safe to display (e.g. "jg_a1b2c3")
    attribute :prefix, :string, allow_nil?: false, public?: true

    # SHA-256 hash of the full key — never store the raw key
    attribute :key_hash, :string do
      allow_nil? false
      sensitive? true
    end

    attribute :last_used_at, :utc_datetime_usec

    timestamps()
  end

  relationships do
    belongs_to :project, Jagua.Projects.Project, allow_nil?: false
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      # Caller generates the raw key externally, passes prefix + key_hash
      accept [:name, :project_id, :prefix, :key_hash]
    end

    update :touch do
      accept []
      change set_attribute(:last_used_at, &DateTime.utc_now/0)
    end

    read :by_key_hash do
      argument :key_hash, :string, allow_nil?: false
      filter expr(key_hash == ^arg(:key_hash))
    end

    read :for_project do
      argument :project_id, :uuid, allow_nil?: false
      filter expr(project_id == ^arg(:project_id))
    end
  end
end
