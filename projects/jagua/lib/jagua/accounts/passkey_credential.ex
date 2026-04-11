defmodule Jagua.Accounts.PasskeyCredential do
  use Ash.Resource,
    domain: Jagua.Accounts,
    data_layer: AshPostgres.DataLayer

  @moduledoc """
  Schema for WebAuthn/passkey credentials. Not wired to the UI in v1 —
  placeholder to avoid a migration later.
  """

  postgres do
    table "passkey_credentials"
    repo Jagua.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :credential_id, :binary, allow_nil?: false
    attribute :public_key, :binary, allow_nil?: false
    attribute :sign_count, :integer, default: 0

    timestamps()
  end

  identities do
    identity :unique_credential, [:credential_id]
  end

  relationships do
    belongs_to :user, Jagua.Accounts.User, allow_nil?: false
  end

  actions do
    defaults [:read, :create, :destroy]
  end
end
