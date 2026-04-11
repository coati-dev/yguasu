defmodule Jagua.Projects.Membership do
  use Ash.Resource,
    domain: Jagua.Projects,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "project_memberships"
    repo Jagua.Repo
  end

  attributes do
    uuid_primary_key :id
    timestamps()
  end

  identities do
    identity :unique_membership, [:project_id, :user_id]
  end

  relationships do
    belongs_to :project, Jagua.Projects.Project, allow_nil?: false
    belongs_to :user, Jagua.Accounts.User, allow_nil?: false
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:project_id, :user_id]
    end
  end
end
