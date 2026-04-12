# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
mix setup              # First-time setup: deps, DB, migrations, assets
mix test               # Run all tests (auto creates/migrates test DB)
mix test test/path/to/test_file.exs          # Run a single test file
mix test test/path/to/test_file.exs:42       # Run a single test by line
mix phx.server         # Start dev server at localhost:4000
mix ecto.reset         # Drop and recreate DB with migrations
```

## Architecture

### Domains (Ash Framework)

Jagua uses [Ash Framework](https://ash-hq.org) for the data layer. Each domain (`lib/jagua/<domain>/`) is an `Ash.Domain` module grouping related resources:

- **Accounts** — `User`, `MagicLink` (passwordless auth tokens), `PasskeyCredential`
- **Projects** — `Project` (name, slug, owner_id, public_status_page), `Membership` (team members)
- **Sentinels** — `Sentinel` (the core resource), `CheckIn` (event log)
- **Alerts** — `AlertChannel` (email/telegram/webhook destinations), `AlertEvent` (audit log)
- **ApiKeys** — `ApiKey` (per-project Bearer tokens for the REST API)

**Ash usage pattern:**
```elixir
# Reads
Sentinel |> Ash.Query.for_read(:by_token, %{token: token}) |> Ash.read_one(domain: Jagua.Sentinels)

# Writes
sentinel |> Ash.Changeset.for_update(:check_in, %{exit_code: 0}) |> Ash.update!(domain: Jagua.Sentinels)
```

### OTP Supervision Tree

```
Jagua.Application
├── Repo                       (AshPostgres/Ecto)
├── PubSub                     (Phoenix pub/sub for LiveView)
├── Finch                      (HTTP client for webhooks/Telegram)
├── RateLimiter                (ETS-based fixed-window rate limiter)
├── Registry (Sentinel.Timer)  (named process lookup)
├── Sentinel.Supervisor        (DynamicSupervisor — one Timer per active sentinel)
├── Sentinel.Loader            (GenServer — starts all Timers on boot)
└── Endpoint
```

**`Sentinel.Timer`** (`lib/jagua/sentinel/timer.ex`) is the core of the monitoring logic. One GenServer per active sentinel:
- Computes UTC-aligned window boundaries for the sentinel's interval
- Tracks `check_in_received?` and `status` in state (`:pending` until first check-in)
- Fires alerts via `Jagua.Alerts.Dispatcher` when a window closes with no check-in
- Implements **smart alerts**: after ≥5 check-ins, fires early at µ + 2σ of observed offsets
- Sends reminder notifications for pending/paused sentinels after 3 days
- **Important**: `:pending` sentinels must never be marked `:failed` — guard all alert paths on `state.status != :pending`

**`Sentinel.Loader`** queries all non-paused sentinels on startup and spawns a Timer for each. When sentinels are paused/unpaused/deleted via LiveView, call `Jagua.Sentinel.Supervisor` directly.

### Authentication

**Magic link (browser):** `JaguaWeb.UserAuth` plugs + on_mount hooks. Flow: email → `Jagua.Accounts.Auth.request_magic_link/1` → SHA-256 hashed token → email → user clicks → `confirm_magic_link/1` consumes token → session. Open registration (creates user if email is new).

**Bearer token (API):** `JaguaWeb.Plugs.ApiAuth` hashes the `Authorization: Bearer <key>` value and looks up the `ApiKey` resource. Keys are scoped to a single project.

### Router Pipelines

- `:check_in` — no CSRF, rate-limited (60/min per token)
- `:api_auth` — JSON + Bearer token + rate-limited (600/min per key)
- `:require_auth` — halts if no session user

### LiveView Conventions

- All authenticated LiveViews use `on_mount: [{JaguaWeb.UserAuth, :ensure_authenticated}]`
- Use `push_navigate` (not `push_patch`) when the URL changes significantly or the LiveView doesn't implement `handle_params/3`
- Flash messages use `put_flash(socket, :info | :error, "message")`

### Check-in Endpoint

`GET|POST /in/:token` — no auth, token is the credential. Query params: `m=message`, `s=exit_code` (0 = healthy, non-zero = errored). After recording the check-in, calls `Jagua.Sentinel.Timer.notify_check_in(sentinel.id)` to reset the OTP timer.

### Rate Limiter

`Jagua.RateLimiter` uses ETS with atomic counters. Fixed-window keyed by `{type, identifier, window_id}`. Fails open if ETS is unavailable.

## Production Environment Variables

| Variable | Description |
|---|---|
| `DATABASE_URL` | PostgreSQL connection string |
| `SECRET_KEY_BASE` | Phoenix secret (generate with `mix phx.gen.secret`) |
| `PHX_HOST` | Domain, e.g. `jagua.example.com` |
| `PORT` | HTTP port (default 4000) |
| `SMTP_*` | Mail server config (see `config/runtime.exs`) |

## Commit Co-authors

Every commit must include Coati co-author:

```
Co-Authored-By: Coati <mig4ng+coati@gmail.com>
```

## Commits

All commits must follow default git convention.
No feat:, fix:, etc.
