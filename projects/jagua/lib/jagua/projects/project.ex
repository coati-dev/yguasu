defmodule Jagua.Projects.Project do
  use Ash.Resource,
    domain: Jagua.Projects,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "projects"
    repo Jagua.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :slug, :string do
      allow_nil? false
      public? true
    end

    attribute :public_status_page, :boolean, default: false, public?: true

    timestamps()
  end

  identities do
    identity :unique_slug, [:slug]
  end

  relationships do
    belongs_to :owner, Jagua.Accounts.User, allow_nil?: false
    has_many :memberships, Jagua.Projects.Membership
    has_many :sentinels, Jagua.Sentinels.Sentinel
    has_many :api_keys, Jagua.ApiKeys.ApiKey
    has_many :alert_channels, Jagua.Alerts.AlertChannel
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :slug, :owner_id]
    end

    update :update do
      accept [:name, :slug, :public_status_page]
    end

    read :for_user do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(owner_id == ^arg(:user_id) or exists(memberships, user_id == ^arg(:user_id)))
    end

    read :by_slug do
      argument :slug, :string, allow_nil?: false
      filter expr(slug == ^arg(:slug))
    end
  end
end
