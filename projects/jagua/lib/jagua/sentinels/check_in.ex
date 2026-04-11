defmodule Jagua.Sentinels.CheckIn do
  use Ash.Resource,
    domain: Jagua.Sentinels,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "sentinel_check_ins"
    repo Jagua.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :message, :string
    attribute :exit_code, :integer, default: 0

    attribute :status, :atom do
      default :ok
      constraints one_of: [:ok, :error]
    end

    timestamps()
  end

  relationships do
    belongs_to :sentinel, Jagua.Sentinels.Sentinel, allow_nil?: false
  end

  actions do
    defaults [:read, :destroy]

    create :record do
      accept [:sentinel_id, :message, :exit_code]

      change fn changeset, _ ->
        exit_code = Ash.Changeset.get_attribute(changeset, :exit_code) || 0
        status = if exit_code == 0, do: :ok, else: :error
        Ash.Changeset.force_change_attribute(changeset, :status, status)
      end
    end

    read :for_sentinel do
      argument :sentinel_id, :uuid, allow_nil?: false
      filter expr(sentinel_id == ^arg(:sentinel_id))
    end

    # Used for smart alert statistical analysis
    read :recent_for_sentinel do
      argument :sentinel_id, :uuid, allow_nil?: false
      argument :limit, :integer, default: 50

      filter expr(sentinel_id == ^arg(:sentinel_id))
      prepare build(sort: [inserted_at: :desc], limit: arg(:limit))
    end
  end
end
