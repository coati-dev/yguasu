defmodule Jagua.Accounts.MagicLink do
  use Ash.Resource,
    domain: Jagua.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "magic_links"
    repo Jagua.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :token_hash, :string do
      allow_nil? false
      sensitive? true
    end

    attribute :used_at, :utc_datetime_usec
    attribute :expires_at, :utc_datetime_usec, allow_nil?: false

    timestamps()
  end

  relationships do
    belongs_to :user, Jagua.Accounts.User, allow_nil?: false
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:token_hash, :expires_at, :user_id]
    end

    update :consume do
      accept []
      change set_attribute(:used_at, &DateTime.utc_now/0)
    end

    read :by_token_hash do
      argument :token_hash, :string, allow_nil?: false
      filter expr(token_hash == ^arg(:token_hash) and is_nil(used_at) and expires_at > ^DateTime.utc_now())
    end
  end
end
