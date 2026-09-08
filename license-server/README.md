# Predict-A-Trade License Server (Go)

High-concurrency license validation API for the Predict-A-Trade MQL5 EA — designed for
10,000+ subscribers. Gin + Redis + PostgreSQL, fully containerized.

```
license-server/
├── main.go                  # HTTP server, graceful shutdown
├── internal/
│   ├── api/                 # router, middleware (rate limit + HTTPS), handlers, Stripe webhook
│   ├── db/                  # pgx pool, license/activation/settings stores, migrations helpers
│   ├── cache/               # Redis: validation cache + rate-limit counters (fail-open)
│   ├── models/              # domain types
│   └── config/              # env/.env loading (godotenv)
├── migrations/001_init.sql  # schema: users, licenses, activations, settings, events
├── .env.example             # every variable documented; real .env NEVER committed
├── Dockerfile               # multi-stage, non-root, ~12 MB binary
└── docker-compose.yml       # api + redis + postgres (auto-migrates on first boot)
```

## Build & run

```bash
go build ./...          # compile
go vet ./...            # static analysis (clean)
go test ./...           # routing / HTTPS / headers / key-format smoke tests
docker compose up -d    # full stack; POSTGRES_PASSWORD + DATABASE_URL come from .env
```

## API

| Endpoint | Purpose | Notes |
|---|---|---|
| `POST /v1/activate` | Bind a machine/account seat | checks status/expiry, `max_activations`, upserts seat, caches 1 h |
| `POST /v1/heartbeat` | 10-min keep-alive from the EA | throttled `last_seen_at` writes; serves settings bumps; 60 s cache |
| `POST /v1/webhook/stripe` | billing lifecycle | HMAC-verified; issues/emails keys on `checkout.session.completed`, revokes on `customer.subscription.deleted` |
| `GET /healthz` | liveness | no auth, marks `X-Healthcheck` |

All bodies are JSON. Validation responses: `{"valid":true,"auto_trading_enabled":true,"settings_version":N}`
or `{"valid":false,"reason":"expired_or_revoked|max_activations_reached|invalid_key|not_activated"}`.

## Security model

- Raw license keys are **never stored** — SHA256 hex hashes only.
- Rate limits: 10 req/min/IP, 30 req/min/key (Redis windows, fail-open on Redis errors).
- HTTPS enforced in `APP_ENV=production` (direct TLS or `X-Forwarded-Proto`).
- Stripe webhooks: `t=`/`v1=` signature verification, 5-minute tolerance.
- Machine fingerprint (computed client-side) binds seats to hardware + account + broker.

## Operating notes

- Migrations run automatically on the first `postgres` boot (docker-entrypoint-initdb.d).
- Scale the `api` service horizontally behind the TLS proxy; Postgres handles the rest.
- Revoke manually: `UPDATE licenses SET status='revoked' WHERE ...` then delete the
  matching `lic:<hash>` Redis key (the webhook does both atomically enough for billing
  events).
- Logs contain no keys: activation emails carry the raw key once; everything else logs
  hashes and event types.