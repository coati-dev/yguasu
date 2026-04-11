defmodule Jagua.Accounts.User do
  use Ash.Resource,
    domain: Jagua.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "users"
    repo Jagua.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  identities do
    identity :unique_email, [:email]
  end

  relationships do
    has_many :memberships, Jagua.Projects.Membership
    has_many :magic_links, Jagua.Accounts.MagicLink
    has_many :passkey_credentials, Jagua.Accounts.PasskeyCredential
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:email]
    end

    update :update do
      accept [:email]
    end

    read :by_email do
      argument :email, :ci_string, allow_nil?: false
      filter expr(email == ^arg(:email))
    end
  end
end
