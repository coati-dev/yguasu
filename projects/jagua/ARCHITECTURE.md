# Jagua Architecture

Jagua is a Dead Man's Snitch-style cron job monitor built with Elixir/Phoenix, Ash Framework, Phoenix LiveView, and PostgreSQL. Jobs ping an HTTP endpoint on each run; if a ping is missed, alerts fire.

---

## Table of Contents

1. [OTP Supervision Tree](#otp-supervision-tree)
2. [Sentinel Lifecycle](#sentinel-lifecycle)
3. [Data Model (Ash Domains)](#data-model-ash-domains)
4. [Request Paths](#request-paths)
5. [Authentication Flows](#authentication-flows)
6. [Alert Dispatching](#alert-dispatching)
7. [Key Design Decisions](#key-design-decisions)

---

## OTP Supervision Tree

```mermaid
graph TD
    App["Jagua.Supervisor\n(one_for_one)"]

    App --> Telemetry["JaguaWeb.Telemetry\n(Phoenix metrics)"]
    App --> Repo["Jagua.Repo\n(AshPostgres/Ecto)"]
    App --> DNS["DNSCluster\n(cluster DNS, noop in dev)"]
    App --> PubSub["Phoenix.PubSub\nJagua.PubSub"]
    App --> Finch["Finch\nJagua.Finch\n(HTTP client pool)"]
    App --> RL["Jagua.RateLimiter\n(GenServer owns ETS table)"]
    App --> Reg["Registry\nJagua.Sentinel.Registry\n(:unique, per-sentinel name lookup)"]
    App --> DS["DynamicSupervisor\nJagua.Sentinel.Supervisor\n(one_for_one)"]
    App --> Loader["Jagua.Sentinel.Loader\n(GenServer, boot loader)"]
    App --> Endpoint["JaguaWeb.Endpoint\n(Bandit HTTP server)"]

    DS -->|"one child per\nactive sentinel"| Timer1["Sentinel.Timer\n:sentinel_id_A"]
    DS --> Timer2["Sentinel.Timer\n:sentinel_id_B"]
    DS --> TimerN["Sentinel.Timer\n:sentinel_id_..."]

    Loader -->|"on boot: ensure_started\nfor all active sentinels"| DS

    style App fill:#4B5563,color:#fff
    style DS fill:#1D4ED8,color:#fff
    style Loader fill:#1D4ED8,color:#fff
    style Timer1 fill:#065F46,color:#fff
    style Timer2 fill:#065F46,color:#fff
    style TimerN fill:#065F46,color:#fff
```

### Sentinel.Timer internals

Each `Sentinel.Timer` is a `:transient` GenServer registered via `{:via, Registry, {Jagua.Sentinel.Registry, sentinel_id}}`. It holds three concurrent timers in its state:

```mermaid
graph LR
    subgraph "Sentinel.Timer state"
        MS["Main timer\n:check_window\n(fires at UTC window boundary)"]
        ST["Smart timer\n:smart_check\n(fires at µ+2σ of historical offsets)\nalert_type == :smart only"]
        RT["Reminder timer\n:send_reminder\n(fires 3 days after created_at\nor paused_at)"]
    end

    CI["notify_check_in/1\n(cast from CheckIn endpoint)"] -->|"cancels smart_timer\nsets check_in_received? true"| ST
    MS -->|"no check-in?\nstatus != :pending"| Alert["fire_alert/2\n→ mark_failed\n→ Dispatcher.dispatch"]
    ST -->|"no check-in yet?\nstatus != :pending"| Alert
    RT --> Remind["Dispatcher.dispatch\n:pending_reminder or\n:paused_reminder"]
```

**Window boundary model:** all sentinels sharing the same interval evaluate at the same UTC wall-clock tick (e.g., all `:hourly` sentinels at `:00` each hour). Windows are *not* rolling from creation time — this mirrors Dead Man's Snitch behavior.

---

## Sentinel Lifecycle

```mermaid
stateDiagram-v2
    [*] --> pending : created\n(Timer.ensure_started)
    pending --> healthy : first check-in received\n(exit_code == 0)
    pending --> errored : first check-in received\n(exit_code != 0)
    healthy --> failed : window closes\nwith no check-in
    healthy --> errored : check-in received\n(exit_code != 0)
    errored --> healthy : check-in received\n(exit_code == 0)\n→ :recovered alert
    failed --> healthy : check-in received\n(exit_code == 0)\n→ :recovered alert
    healthy --> paused : user pauses\n(Timer.stop)
    errored --> paused : user pauses\n(Timer.stop)
    failed --> paused : user pauses\n(Timer.stop)
    paused --> pending : user unpauses\n(Timer.ensure_started)

    note right of pending
      Timer never fires :failed
      alerts while :pending.
      Reminder sent after 3 days.
    end note
```

### Check-in endpoint flow

```mermaid
sequenceDiagram
    participant Job as Cron Job
    participant EP as GET|POST /in/:token
    participant DB as Database (Ash)
    participant Timer as Sentinel.Timer

    Job->>EP: GET /in/abc123?s=0&m=OK
    EP->>DB: Sentinel :by_token
    alt sentinel is paused
        EP-->>Job: 200 OK (no state change)
    else sentinel active
        EP->>DB: CheckIn :record (exit_code, message)
        EP->>DB: Sentinel :check_in (update status, last_check_in_at)
        alt previous status was :failed/:errored AND new is :healthy
            EP->>DB: Dispatcher.dispatch(:recovered) [async Task]
        end
        EP->>Timer: notify_check_in(sentinel.id)
        Timer-->>Timer: cancel smart_timer, check_in_received? = true
        EP-->>Job: 200 "Jagua got it! Much obliged."
    end
```

---

## Data Model (Ash Domains)

```mermaid
erDiagram
    User {
        uuid id PK
        ci_string email UK
    }
    Project {
        uuid id PK
        string name
        string slug UK
        uuid owner_id FK
        boolean public_status_page
    }
    Membership {
        uuid id PK
        uuid user_id FK
        uuid project_id FK
    }
    Sentinel {
        uuid id PK
        string name
        string token UK
        atom interval
        atom status
        atom alert_type
        string tags
        datetime last_check_in_at
        datetime next_alert_at
        datetime paused_at
        uuid project_id FK
    }
    CheckIn {
        uuid id PK
        integer exit_code
        string message
        atom status
        uuid sentinel_id FK
    }
    AlertChannel {
        uuid id PK
        string name
        atom type
        map config
        boolean enabled
        uuid project_id FK
    }
    AlertEvent {
        uuid id PK
        atom type
        map payload
        datetime sent_at
        uuid sentinel_id FK
        uuid alert_channel_id FK
    }
    ApiKey {
        uuid id PK
        string name
        string prefix
        string key_hash
        datetime last_used_at
        uuid project_id FK
    }
    MagicLink {
        uuid id PK
        string token_hash
        datetime used_at
        datetime expires_at
        uuid user_id FK
    }

    User ||--o{ Membership : "belongs to"
    User ||--o{ Project : "owns"
    User ||--o{ MagicLink : "has many"
    Project ||--o{ Membership : "has many"
    Project ||--o{ Sentinel : "has many"
    Project ||--o{ AlertChannel : "has many"
    Project ||--o{ ApiKey : "has many"
    Sentinel ||--o{ CheckIn : "has many"
    Sentinel ||--o{ AlertEvent : "has many"
    AlertChannel ||--o{ AlertEvent : "has many"
```

### Ash domains

| Domain | Resources |
|---|---|
| `Jagua.Accounts` | `User`, `MagicLink`, `PasskeyCredential` |
| `Jagua.Projects` | `Project`, `Membership` |
| `Jagua.Sentinels` | `Sentinel`, `CheckIn` |
| `Jagua.Alerts` | `AlertChannel`, `AlertEvent` |
| `Jagua.ApiKeys` | `ApiKey` |

---

## Request Paths

### Router pipelines

```mermaid
graph LR
    subgraph ":browser pipeline"
        B1["fetch_session\nfetch_live_flash\nprotect_from_forgery\nfetch_current_user"]
    end
    subgraph ":require_auth"
        B2["require_authenticated_user\n(halts if no session)"]
    end
    subgraph ":check_in pipeline"
        C1["RateLimit\n60 req/min per token\n(NO CSRF, NO session)"]
    end
    subgraph ":api_auth pipeline"
        A1["ApiAuth plug\n(Bearer token → ApiKey → Project)\nRateLimit 600 req/min per key"]
    end

    Browser["Browser\nGET /dashboard\nlive/*"] --> B1 --> B2
    CheckIn["GET|POST /in/:token"] --> C1
    RestAPI["REST API\n/api/*"] --> A1
```

### All routes at a glance

| Path | Handler | Auth |
|---|---|---|
| `GET /` | `PageController :home` | public |
| `GET /auth/confirm/:token` | `AuthController :confirm` | public |
| `DELETE /auth/logout` | `AuthController :logout` | public |
| `GET /status/:slug` | `Live.StatusPageLive` | public |
| `GET /login` | `Live.LoginLive` | public (redirect if authed) |
| `GET\|POST /in/:token` | `CheckInController :check_in` | token-based, rate-limited |
| `GET /dashboard` | `Live.DashboardLive` | session |
| `GET /projects/new` | `Live.ProjectLive.New` | session |
| `GET /projects/:slug` | `Live.ProjectLive.Show` | session |
| `GET /projects/:slug/sentinels/new` | `Live.SentinelLive.New` | session |
| `GET /projects/:slug/sentinels/:token` | `Live.SentinelLive.Show` | session |
| `GET /projects/:slug/settings` | `Live.ProjectLive.Settings` | session |
| `GET /projects/:slug/api-keys` | `Live.ApiKeysLive` | session |
| `GET /settings` | `Live.SettingsLive` | session |
| `GET\|POST\|PATCH\|DELETE /api/projects` | `Api.ProjectController` | Bearer token |
| `GET\|POST\|PATCH\|DELETE /api/projects/:id/sentinels/:token` | `Api.SentinelController` | Bearer token |
| `GET /api/projects/:id/sentinels/:token/check_ins` | `Api.CheckInController` | Bearer token |

---

## Authentication Flows

### Magic link (browser auth)

```mermaid
sequenceDiagram
    participant User
    participant LoginLive
    participant Auth as Jagua.Accounts.Auth
    participant DB as Database
    participant Email as Mailer
    participant AuthCtrl as AuthController
    participant Session

    User->>LoginLive: submit email
    LoginLive->>Auth: request_magic_link(email)
    Auth->>DB: User :by_email (create if absent)
    Auth->>DB: MagicLink :create (token_hash = SHA-256(raw), expires_at = now+15m)
    Auth->>Email: send link /auth/confirm/:raw_token
    Auth-->>LoginLive: :ok (always, prevents enumeration)
    LoginLive-->>User: "Check your inbox"

    User->>AuthCtrl: GET /auth/confirm/:raw_token
    AuthCtrl->>DB: MagicLink :by_token_hash (SHA-256 lookup, filters used/expired)
    AuthCtrl->>DB: MagicLink :consume (sets used_at)
    AuthCtrl->>Session: put user_id, set _jagua_user cookie (60d)
    AuthCtrl-->>User: redirect /dashboard
```

### API Bearer token auth

```mermaid
sequenceDiagram
    participant Client
    participant ApiAuth as ApiAuth Plug
    participant DB as Database
    participant Controller

    Client->>ApiAuth: Authorization: Bearer jg_<48 hex>
    ApiAuth->>DB: ApiKey :by_key_hash (SHA-256 lookup)
    ApiAuth->>DB: preload Project
    ApiAuth->>DB: ApiKey :touch (async Task, updates last_used_at)
    ApiAuth-->>Controller: conn with :current_api_key, :current_project
    Controller->>Controller: validate current_project.id == params["project_id"]
    Controller-->>Client: JSON response
```

---

## Alert Dispatching

```mermaid
graph TD
    Trigger["Alert trigger\n(Timer :check_window\nor :smart_check)"]
    Trigger --> FA["fire_alert/2\n→ Sentinel :mark_failed\n→ Dispatcher.dispatch(sentinel, :failed)"]

    FA --> Query["AlertChannel :for_project\n(enabled channels only)"]
    Query --> Loop["for each channel..."]

    Loop --> Task["Jagua.Tasks.start\n(async Task)"]

    Task --> Email["Channels.Email.send\n→ Swoosh email\n(to channel.config.emails)"]
    Task --> TG["Channels.Telegram.send\n→ Finch POST\napi.telegram.org/sendMessage"]
    Task --> WH["Channels.Webhook.send\n→ Finch POST\n(:json or :slack format)"]

    Email --> Record["AlertEvent :record\n(audit log)"]
    TG --> Record
    WH --> Record

    subgraph "Alert types"
        AT[":failed\n:errored\n:recovered\n:pending_reminder\n:paused_reminder"]
    end
```

### Alert channel types

| Type | Config fields | Delivery |
|---|---|---|
| `:email` | `emails` (list) | Swoosh via SMTP |
| `:telegram` | `bot_token`, `chat_id` | Finch → Telegram Bot API (MarkdownV2) |
| `:webhook` | `url`, `format` (`:json`/`:slack`) | Finch POST with JSON payload |

---

## Key Design Decisions

### 1. Fixed UTC window boundaries

All sentinels with the same interval share global wall-clock boundaries (`Jagua.Sentinel.Schedule`). An `:hourly` sentinel fires its check at `:00` every hour regardless of when it was created — not 60 minutes from creation. This matches Dead Man's Snitch semantics and makes missed-window reasoning simpler.

### 2. Smart alert mode

When `alert_type == :smart` and the sentinel has at least 5 historical check-ins, the Timer computes `µ + 2σ` of the observed offsets within each window and schedules a `:smart_check` message at that time. This fires the alert *before* the window closes if the job is statistically very late, reducing MTTD.

### 3. Pending sentinels never fail

A sentinel in `:pending` state (no check-in ever received) cannot transition to `:failed`. All alert dispatch paths guard on `state.status != :pending`. This prevents false alerts for newly created monitors before the first run of the job.

### 4. No raw credential storage

- **API keys**: only `prefix` (12 chars, safe to display) + `key_hash` (SHA-256) stored. Raw key shown once in the UI.
- **Magic links**: only `token_hash` (SHA-256) stored. Raw token travels only in the email link.
- **Check-in tokens**: stored in plaintext (they are not secrets — they identify a sentinel, not a user).

### 5. Async tasks for non-critical work

`Jagua.Tasks.start/1` wraps `Task.start` for fire-and-forget work (alert sends, `last_used_at` touches). In test mode (`config :jagua, async_tasks: false`) it runs synchronously to avoid Ecto sandbox teardown races.

### 6. Open registration

`Auth.request_magic_link/1` creates a `User` record if the email is unknown. There is no separate sign-up form. The response is always `:ok` to prevent email enumeration attacks.

### 7. Rate limiting

`Jagua.RateLimiter` uses an ETS table with atomic counters (fixed-window, no GenServer call per request). Fails open if the ETS table is unavailable. Two tiers:
- Check-in endpoint: 60 req/min keyed by sentinel token
- REST API: 600 req/min keyed by API key ID
