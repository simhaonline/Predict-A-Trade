# License System Guide

Server-side validation for Predict-A-Trade-Ultra: a Go license API (Redis + PostgreSQL,
built for 10,000+ subscribers) plus the MQL5 license client built into the EA. All of it
is **optional** — `InpLicenseKey=""` runs the EA in unrestricted local mode with zero
overhead.

## 1. Architecture

```
MT5 EA (Predict-A-Trade-Ultra.mq5)
   │  HTTPS POST /v1/activate (once at init)
   │  HTTPS POST /v1/heartbeat (every 10 min, OnTimer ONLY)
   ▼
TLS terminator (nginx / Caddy / LB)
   ▼
Go API  ──── Redis (hot cache: validation state, rate-limit counters)
   │
   └──── PostgreSQL (licenses, activations, settings, events)
              ▲
Stripe webhook ── checkout.session.completed → issue & email key
                  customer.subscription.deleted → revoke
```

Data flow rules:
- The EA sends the raw key over HTTPS; the server stores only its **SHA256 hash**.
- Redis answers repeated heartbeats (TTL 60 s for heartbeats, 1 h for activations);
  PostgreSQL is hit on cache miss and for seat bookkeeping.
- `WebRequest` in the EA happens **only inside `OnTimer()`** — never in the tick path.

## 2. Server deployment (docker-compose)

```bash
cd license-server
cp .env.example .env         # set DATABASE_URL, POSTGRES_PASSWORD, Stripe secrets
docker compose up -d         # api + redis + postgres; migrations apply on first boot
curl http://localhost:8080/healthz
```

Front the API with TLS (required in production — the API rejects plain HTTP unless
`APP_ENV=development` or the request carries `X-Forwarded-Proto: https`):

```nginx
server {
  listen 443 ssl;
  server_name api.yourdomain.com;
  location / { proxy_pass http://127.0.0.1:8080; proxy_set_header X-Forwarded-Proto https; }
}
```

Verify: `go test ./...` (routing, HTTPS enforcement, headers, key format), `go vet ./...`.

## 3. Stripe integration

1. Dashboard → Developers → Webhooks → add endpoint: `https://api.yourdomain.com/v1/webhook/stripe`.
2. Subscribe to `checkout.session.completed` and `customer.subscription.deleted`.
3. Put the signing secret into `STRIPE_WEBHOOK_SECRET` in `.env`.
4. The handler verifies the `Stripe-Signature` HMAC (v1 scheme, 5-min tolerance), then:
   - **completed**: generates a `PAT-XXXX-XXXX-XXXX-XXXX` key (crypto-random, no
     ambiguous glyphs), stores the hash, creates the license + settings row, emails the
     **raw key once** (never logged, never stored).
   - **deleted**: flips `status='revoked'` and evicts the Redis entry so the next
     heartbeat fails.

## 4. MT5 user setup

1. Load a preset (e.g. `XAUUSD_M1_UltraScalp_Licensed.set`).
2. Enter the purchased key into `InpLicenseKey`.
3. Tools → Options → Expert Advisors → **Allow WebRequest for listed URL** → add the
   server base URL (e.g. `https://api.yourdomain.com`). Without this the EA logs the
   4014 fix hint and cannot reach the server.
4. Attach to an XAUUSD M1 chart. First validation happens in `OnInit`; failure without
   an active grace period refuses to start (`INIT_FAILED`).

Behavior matrix:

| Situation | Behavior |
|---|---|
| `InpLicenseKey=""` | Local mode — license code never runs, zero overhead |
| Server reachable, key valid | Trading proceeds; state cached 10 min |
| Server unreachable, previously valid | **Grace period** (`InpLicenseGraceMinutes`, default 720 = 12 h) — trading continues |
| Grace expires | New entries blocked; open positions still managed |
| Server says `valid:false` | Blocked immediately; with `InpCloseOnLicenseRevoke=true` positions are flattened via the existing breaker path |
| First run, never validated, server down | `INIT_FAILED` — refuses to start unlicensed |

The license gate (`LicenseCheckGate`) sits at the top of `OnTick` and `TryArm` and
sets the dashboard gate reason to `LICENSE: <reason>` when it blocks.

## 5. Mobile control (MT5 iOS/Android)

No app required — the bridge reads **pending-order comments**:

| Do this on mobile | Effect |
|---|---|
| New order (any pending type, any volume), comment `STOP_EA` | EA stops opening trades |
| comment `START_EA` | EA resumes |
| comment `RISK_0.2` | Risk override 0.2% (0 < risk ≤ 5.0 enforced) |

The EA deletes the command order immediately and applies the state change. Manual
delete/reject of the order also works — it is a one-shot command, not a working order.
`PAT_TRADING_ENABLED` / `PAT_RISK_OVERRIDE` persist as terminal Global Variables across
restarts. Note: this control surface is convenience-only; the capital-protection
breakers (daily loss, consecutive losses, floating DD) can never be lifted from mobile.

## 6. Security notes

- **Keys are hashed**: a database dump exposes no usable keys; raw keys exist only in
  the activation email and the subscriber's EA input.
- **Machine binding**: `machine_id = SHA256(computer|data-path|account|broker-server)`;
  activation seats are `(license, machine, account, broker)` unique tuples with
  `max_activations` enforced. Moving a VPS or broker re-activates under the same cap.
- **Rate limiting**: 10 req/min per IP and 30 req/min per key via Redis `INCR` windows
  (fail-open on Redis outage so monitoring never blocks paying users). Exceeding returns
  HTTP 429 with `retry_after_sec`.
- **Grace period**: protects subscribers from transient VPS/network outages; the
  deadline is set on the first failure and survives until used or refreshed. An EA that
  has never validated gets no grace — it cannot start offline.
- **HTTPS enforced** in production (direct TLS or `X-Forwarded-Proto` from the proxy).
- **No secrets in the repo**: everything sensitive comes from `.env` (server) or EA
  inputs (client). `.env.example` documents the variables; `.env` must never be committed.