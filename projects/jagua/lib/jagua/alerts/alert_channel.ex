defmodule Jagua.Alerts.AlertChannel do
  use Ash.Resource,
    domain: Jagua.Alerts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "alert_channels"
    repo Jagua.Repo
  end

  # Supported channel types
  # email    — Swoosh, SMTP-agnostic
  # telegram — Bot API
  # webhook  — Generic JSON or Slack-compatible POST
  @channel_types ~w(email telegram webhook)

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true

    attribute :type, :atom do
      allow_nil? false
      public? true
      constraints one_of: Enum.map(@channel_types, &String.to_atom/1)
    end

    # Channel-specific config stored as a map, e.g.:
    # email:    %{emails: ["ops@example.com"]}
    # telegram: %{bot_token: "...", chat_id: "..."}
    # webhook:  %{url: "https://...", format: "json" | "slack"}
    attribute :config, :map, default: %{}, sensitive?: true

    attribute :enabled, :boolean, default: true, public?: true

    timestamps()
  end

  relationships do
    belongs_to :project, Jagua.Projects.Project, allow_nil?: false
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :type, :config, :project_id]
    end

    update :update do
      accept [:name, :config, :enabled]
    end

    read :for_project do
      argument :project_id, :uuid, allow_nil?: false
      filter expr(project_id == ^arg(:project_id) and enabled == true)
    end
  end
end
