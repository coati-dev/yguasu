defmodule Jagua.Alerts.AlertEvent do
  use Ash.Resource,
    domain: Jagua.Alerts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "alert_events"
    repo Jagua.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :type, :atom do
      allow_nil? false
      constraints one_of: [:failed, :errored, :recovered, :pending_reminder, :paused_reminder]
    end

    attribute :payload, :map, default: %{}
    attribute :sent_at, :utc_datetime_usec

    timestamps()
  end

  relationships do
    belongs_to :sentinel, Jagua.Sentinels.Sentinel, allow_nil?: false
    belongs_to :alert_channel, Jagua.Alerts.AlertChannel, allow_nil?: false
  end

  actions do
    defaults [:read]

    create :record do
      accept [:sentinel_id, :alert_channel_id, :type, :payload]
      change set_attribute(:sent_at, &DateTime.utc_now/0)
    end
  end
end
