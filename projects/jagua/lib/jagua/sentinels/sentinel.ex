defmodule Jagua.Sentinels.Sentinel do
  use Ash.Resource,
    domain: Jagua.Sentinels,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "sentinels"
    repo Jagua.Repo
  end

  # Valid intervals matching the fixed UTC window schedule
  @intervals ~w(
    1_minute 2_minute 3_minute 5_minute 10_minute 15_minute 20_minute 30_minute
    hourly 2_hour 3_hour 4_hour 6_hour 8_hour 12_hour
    daily weekly monthly
  )

  # Sentinel lifecycle statuses
  # pending  - created but never checked in
  # healthy  - checked in within the expected window
  # failed   - missed a check-in window
  # errored  - checked in but reported a non-zero exit code
  # paused   - monitoring suspended
  @statuses ~w(pending healthy failed errored paused)

  @alert_types ~w(basic smart)

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true

    attribute :token, :string do
      allow_nil? false
      public? true
    end

    attribute :interval, :atom do
      allow_nil? false
      public? true
      constraints one_of: Enum.map(@intervals, &String.to_atom/1)
    end

    attribute :status, :atom do
      default :pending
      public? true
      constraints one_of: Enum.map(@statuses, &String.to_atom/1)
    end

    attribute :alert_type, :atom do
      default :basic
      public? true
      constraints one_of: Enum.map(@alert_types, &String.to_atom/1)
    end

    attribute :notes, :string, public?: true
    attribute :tags, {:array, :string}, default: [], public?: true

    attribute :paused_at, :utc_datetime_usec
    attribute :last_check_in_at, :utc_datetime_usec
    attribute :next_alert_at, :utc_datetime_usec

    timestamps()
  end

  identities do
    identity :unique_token, [:token]
  end

  relationships do
    belongs_to :project, Jagua.Projects.Project, allow_nil?: false
    has_many :check_ins, Jagua.Sentinels.CheckIn
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :interval, :alert_type, :notes, :tags, :project_id]
      change fn changeset, _ ->
        token = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
        Ash.Changeset.force_change_attribute(changeset, :token, token)
      end
    end

    update :update do
      accept [:name, :interval, :alert_type, :notes, :tags]
    end

    update :check_in do
      require_atomic? false
      accept []
      argument :exit_code, :integer, default: 0
      argument :message, :string

      change fn changeset, _ ->
        exit_code = Ash.Changeset.get_argument(changeset, :exit_code) || 0
        status = if exit_code == 0, do: :healthy, else: :errored

        changeset
        |> Ash.Changeset.force_change_attribute(:status, status)
        |> Ash.Changeset.force_change_attribute(:last_check_in_at, DateTime.utc_now())
      end
    end

    update :pause do
      require_atomic? false
      accept []
      change fn changeset, _ ->
        changeset
        |> Ash.Changeset.force_change_attribute(:status, :paused)
        |> Ash.Changeset.force_change_attribute(:paused_at, DateTime.utc_now())
      end
    end

    update :unpause do
      require_atomic? false
      accept []
      change fn changeset, _ ->
        changeset
        |> Ash.Changeset.force_change_attribute(:status, :pending)
        |> Ash.Changeset.force_change_attribute(:paused_at, nil)
      end
    end

    update :mark_failed do
      accept []
      change set_attribute(:status, :failed)
    end

    read :by_token do
      argument :token, :string, allow_nil?: false
      filter expr(token == ^arg(:token))
    end

    read :active do
      filter expr(status != :paused)
    end

    read :for_project do
      argument :project_id, :uuid, allow_nil?: false
      filter expr(project_id == ^arg(:project_id))
    end
  end

end
