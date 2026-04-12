# Jagua

**Job monitoring for scheduled tasks and automations.**

Jagua watches your cron tasks and background jobs by expecting periodic HTTP check-ins.
If a job fails to check in on time, Jagua alerts you via email, Telegram, or webhook.

Named after *Teju Jagua* — the guardian of Guaraní mythology who waits in silence
and strikes in the right moment.

Hosted version coming soon at [jagua.coati.dev](https://jagua.coati.dev).

---

## Features

- **Sentinels** — one per job, each with a unique check-in URL and configurable interval
- **Smart alerts** — learns your job's typical check-in time (µ + 2σ) and alerts early if it's late
- **Multi-channel notifications** — email, Telegram bot, generic JSON webhook, Slack-compatible webhook
- **Activity heatmap** — a year of check-in history color-coded by health
- **Public status pages** — shareable per-project status page, no login required
- **REST API** — manage projects and sentinels programmatically with per-project API keys
- **Multi-tenant** — projects, team members, and alert channels are fully isolated
- **Self-hostable** — plain Elixir/Phoenix/PostgreSQL, no external queue or scheduler required

---

## Check-in endpoint

Each sentinel has a unique token. Check in by making a request to:

```
GET  https://jagua.coati.dev/in/<token>
POST https://jagua.coati.dev/in/<token>
```

Optional query parameters:

| Parameter | Description |
|---|---|
| `m=<message>` | Attach a message to the check-in (shown in activity log) |
| `s=<exit_code>` | Exit code — `0` marks the check-in as healthy, anything else as errored |

**Examples:**

```bash
# Simple check-in
curl https://jagua.coati.dev/in/abc123

# With exit code from the previous command
my-backup-script.sh; curl "https://jagua.coati.dev/in/abc123?s=$?"

# With a message
curl "https://jagua.coati.dev/in/abc123?m=processed+1024+records&s=0"
```

---

## REST API

Authenticate with a project API key:

```
Authorization: Bearer <api_key>
```

API keys are scoped to a single project and managed in the project's API keys page.

### Projects

```
GET    /api/projects
POST   /api/projects
GET    /api/projects/:id
PATCH  /api/projects/:id
DELETE /api/projects/:id
```

### Sentinels

```
GET    /api/projects/:id/sentinels
POST   /api/projects/:id/sentinels
GET    /api/projects/:id/sentinels/:token
PATCH  /api/projects/:id/sentinels/:token
DELETE /api/projects/:id/sentinels/:token
POST   /api/projects/:id/sentinels/:token/pause
POST   /api/projects/:id/sentinels/:token/unpause
```

### Check-ins (read-only)

```
GET    /api/projects/:id/sentinels/:token/check_ins?limit=50
```

`limit` defaults to 50, maximum 200.

---

## Self-hosting

Jagua is a standard Phoenix application backed by PostgreSQL.

**Requirements:** Elixir 1.14+, PostgreSQL 14+

```bash
git clone https://github.com/coati-dev/yguasu
cd yguasu/projects/jagua
mix setup
mix phx.server
```

Visit [localhost:4000](http://localhost:4000).

**Environment variables for production:**

| Variable | Description |
|---|---|
| `DATABASE_URL` | PostgreSQL connection string |
| `SECRET_KEY_BASE` | Phoenix secret key (generate with `mix phx.gen.secret`) |
| `PHX_HOST` | Your domain, e.g. `jagua.example.com` |
| `SMTP_*` | Mail server config (see `config/runtime.exs`) |

---

## Stack

- [Elixir](https://elixir-lang.org) + [Phoenix LiveView](https://github.com/phoenixframework/phoenix_live_view)
- [Ash Framework](https://ash-hq.org) — resource layer and API generation
- [PostgreSQL](https://www.postgresql.org)
- [Tailwind CSS](https://tailwindcss.com)

---

## License

MIT
