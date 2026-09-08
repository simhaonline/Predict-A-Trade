# CODEX CLI TASK — Predict-A-Trade EA: License Validation, Go Backend & Remote Mobile Control

## 0. ROLE & MISSION

You are a Full-Stack Quant & DevOps engineer working on the **Predict-A-Trade** MQL5 EA and its new **Go License Server**.

Your mission is to build a lightweight, high-concurrency license validation system capable of handling **10,000+ subscribers** and integrate it cleanly into the existing MQL5 EA without disrupting the ultra-scalp trading logic.

**Deliverables:**
1. A complete Go backend (API + Redis + PostgreSQL + Webhooks).
2. MQL5 EA integration (License Client + Mobile Command Bridge).
3. Documentation and deployment manifests.

---

## 1. NON-NEGOTIABLE INVARIANTS (MQL5 Side)

1. **Never block `OnTick`**: `WebRequest` calls MUST ONLY happen inside `OnTimer()`. 
2. **Fail-safe Grace Period**: If the server is unreachable but the last known state was `valid`, allow trading for `InpLicenseGracePeriodMinutes`. If the EA has never successfully validated, block trading.
3. **Additive Only**: If `InpLicenseKey == ""`, the EA runs unrestricted (local mode). If a key is provided, the license gate activates.
4. **No Hardcoded Secrets**: API keys, webhook secrets, and DB passwords must live in `.env` (Go) or EA inputs (MQL5). Never commit secrets.
5. **HTTPS Only**: The MQL5 client must enforce `https://`. 
6. **Zero Compile Warnings**: MQL5 strict mode, Go standard linting.

---

# PHASE 1: GO LICENSE SERVER BACKEND

Build the Go backend based on the architecture provided, enhancing it with the advanced database schema and security features.

## 1.1 Project Structure
Create a new directory `license-server/` in the repository root:
```text
license-server/
├── main.go
├── internal/
│   ├── api/
│   │   ├── router.go
│   │   ├── middleware.go      // Rate limiting, HTTPS redirect
│   │   └── handlers.go        // Activate, Heartbeat, Deactivate, Webhook
│   ├── db/
│   │   └── postgres.go
│   ├── cache/
│   │   └── redis.go
│   ├── models/
│   │   └── license.go
│   └── config/
│       └── config.go          // Viper/Godotenv loading
├── migrations/
│   └── 001_init.sql
├── .env.example
├── Dockerfile
├── docker-compose.yml
└── go.mod
```

## 1.2 Database Schema (`migrations/001_init.sql`)
Implement the robust relational schema:
```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE licenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    license_key_hash TEXT UNIQUE NOT NULL, -- SHA256 hash of the key
    status TEXT NOT NULL DEFAULT 'active', -- active, expired, revoked
    plan TEXT DEFAULT 'monthly',
    max_activations INT DEFAULT 2,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE activations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    license_id UUID REFERENCES licenses(id),
    machine_id TEXT NOT NULL,
    account_login BIGINT NOT NULL,
    broker_server TEXT NOT NULL,
    last_seen_at TIMESTAMPTZ DEFAULT NOW(),
    revoked BOOLEAN DEFAULT FALSE,
    UNIQUE(license_id, machine_id, account_login, broker_server)
);

CREATE TABLE license_settings (
    license_id UUID PRIMARY KEY REFERENCES licenses(id),
    auto_trading_enabled BOOLEAN DEFAULT TRUE,
    settings_json JSONB DEFAULT '{}',
    settings_version INT DEFAULT 1,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE license_events (
    id BIGSERIAL PRIMARY KEY,
    license_id UUID,
    event_type TEXT, -- activation, heartbeat, revoked, invalid_key
    ip_address TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_license_key_hash ON licenses(license_key_hash);
CREATE INDEX idx_activations_license ON activations(license_id);
```

## 1.3 Go API Endpoints & Logic

Implement the following REST/JSON endpoints using `gin-gonic/gin`:

### `POST /v1/activate`
- **Input**: `{ "license_key": "...", "machine_id": "...", "account_login": 123, "broker_server": "..." }`
- **Logic**: 
  1. Hash the `license_key` with SHA256.
  2. Check Redis cache, then PostgreSQL `licenses` table.
  3. If `status != 'active'` or `expires_at < NOW()`, return `{ "valid": false, "reason": "expired/revoked" }`.
  4. Check `activations` count for this license. If `count >= max_activations`, return `{ "valid": false, "reason": "max_activations_reached" }`.
  5. Upsert into `activations` (update `last_seen_at`).
  6. Cache in Redis with TTL of 1 hour.
  7. Return `{ "valid": true, "settings_version": 1, "auto_trading_enabled": true }`.

### `POST /v1/heartbeat`
- **Input**: `{ "license_key": "...", "machine_id": "...", "account_login": 123, "settings_version": 12 }`
- **Logic**:
  1. Check Redis/Postgres for valid license and matching activation.
  2. Update `last_seen_at` in DB (throttled, e.g., only update if > 1 hour old).
  3. If `request.settings_version < DB.settings_version`, fetch from `license_settings` and include in response.
  4. Return `{ "valid": true, "auto_trading_enabled": true, "settings_version": 12 }`.

### `POST /v1/webhook/stripe`
- **Logic**: Verify Stripe signature. On `checkout.session.completed`, generate a secure random license key, hash it, insert into `licenses`, and email the key to the customer. On `customer.subscription.deleted`, set `status = 'revoked'` and delete from Redis.

### Middleware
- **Rate Limiting**: Use Redis to enforce 10 req/min per IP and 30 req/min per License Key.
- **HTTPS**: Reject non-TLS requests in production.

## 1.4 Docker & Deployment
Create `Dockerfile` (multi-stage Alpine build for ~18MB image) and `docker-compose.yml` (Go API + Redis + Postgres) for easy VPS deployment.

---

# PHASE 2: MQL5 LICENSE CLIENT INTEGRATION

Integrate the client into the Predict-A-Trade EA. All new code gated by `InpLicenseKey`.

## 2.1 New Inputs
```mql5
input string InpLicenseKey            = "";   // Leave blank for local/unlimited mode
input string InpLicenseServerURL      = "https://api.yourdomain.com"; // License Server URL
input int    InpLicenseGraceMinutes   = 720;  // Grace period if server unreachable (mins)
input bool   InpCloseOnLicenseRevoke  = false;// Close positions if license revoked?
```

## 2.2 Global State Variables
```mql5
bool   g_licenseActive         = false;
bool   g_autoTradingEnabled    = true;
int    g_settingsVersion       = 0;
datetime g_nextLicenseCheck    = 0;
datetime g_gracePeriodDeadline = 0;
string g_machineId             = "";
```

## 2.3 Machine Fingerprinting
In `OnInit()`, generate a stable `g_machineId`:
```mql5
string raw_id = TerminalInfoString(TERMINAL_COMPUTER_NAME) + "|" + 
                TerminalInfoString(TERMINAL_DATA_PATH) + "|" + 
                IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "|" + 
                AccountInfoString(ACCOUNT_SERVER);
g_machineId = SHA256(raw_id); // Implement or use a simple MQL5 hashing snippet
```

## 2.4 OnTimer Polling Logic
Add to `OnTimer()` (ensure `EventSetTimer(30)` is in `OnInit`):
```mql5
if(InpLicenseKey != "" && TimeCurrent() >= g_nextLicenseCheck) {
    CheckLicense(); 
    g_nextLicenseCheck = TimeCurrent() + 600; // Poll every 10 mins
}
```

## 2.5 WebRequest & JSON Parsing
Implement `CheckLicense()`:
1. Build JSON payload: `{"key":"...", "machine_id":"...", "account_login":...}`
2. Call `WebRequest("POST", InpLicenseServerURL + "/v1/heartbeat", ...)` with a 5000ms timeout.
3. If `WebRequest` fails (network error):
   - If `g_licenseActive` was true, enter grace period up to `InpLicenseGraceMinutes`. Log warning.
   - If grace period expires, set `g_licenseActive = false`.
4. If Success (200 OK):
   - Parse JSON body (use rudimentary `StringFind` for `"valid":true` and `"auto_trading_enabled":false`).
   - Update `g_licenseActive` and `g_autoTradingEnabled`.
   - Reset grace period deadline.
5. If API returns `valid: false`:
   - Set `g_licenseActive = false`. Log error reason.

## 2.6 Trading Gate
At the very top of `OnTick()` and `TryArm()`:
```mql5
if(InpLicenseKey != "" && (!g_licenseActive || !g_autoTradingEnabled)) {
    // Do not open new trades
    return; 
}
```

If `g_licenseActive` transitions from `true` to `false` and `InpCloseOnLicenseRevoke == true`, execute the existing `BREAKER_CLOSE_ALL` logic.

## 2.7 Initialization Validation
In `OnInit()`:
- If `InpLicenseKey != ""`, immediately call `CheckLicense()`.
- If it fails and no grace period is active, return `INIT_FAILED` (refuse to start without a valid license on first run).
- Validate that `InpLicenseServerURL` starts with `https://`.

---

# PHASE 3: MQL5 MOBILE COMMAND BRIDGE (PENDING ORDERS)

Allow subscribers to control the EA from the MT5 Mobile App by placing pending orders with specific comments.

## 3.1 Inputs
```mql5
input bool InpEnableMobileCommands = true; // Enable MT5 Mobile App command bridge
```

## 3.2 Command Logic
In `OnTick()` (or `OnTimer()`), if `InpEnableMobileCommands`:
```mql5
for(int i=OrdersTotal()-1; i>=0; i--) {
    ulong ticket = OrderGetTicket(i);
    if(ticket == 0) continue;
    
    string comment = OrderGetString(ORDER_COMMENT);
    
    if(StringFind(comment, "STOP_EA") >= 0) {
        GlobalVariableSet("PAT_TRADING_ENABLED", 0);
        OrderDelete(ticket);
        Print("Mobile Command: STOP_EA");
    }
    else if(StringFind(comment, "START_EA") >= 0) {
        GlobalVariableSet("PAT_TRADING_ENABLED", 1);
        OrderDelete(ticket);
        Print("Mobile Command: START_EA");
    }
    else if(StringFind(comment, "RISK_") >= 0) {
        double risk = StringToDouble(StringSubstr(comment, 5));
        if(risk > 0 && risk <= 5.0) { // Basic safety
            GlobalVariableSet("PAT_RISK_OVERRIDE", risk);
            OrderDelete(ticket);
            Print("Mobile Command: Risk set to ", risk);
        }
    }
}
```
Integrate `GlobalVariableGet("PAT_TRADING_ENABLED")` into the main trading gate.

---

# PHASE 4: DOCUMENTATION & DEPLOYMENT

## 4.1 `docs/License_System_Guide.md`
Must contain:
1. **Architecture Diagram**: EA -> HTTPS -> Go -> Redis/Postgres.
2. **Setup Guide**: How to deploy the Go server using `docker-compose`.
3. **Stripe Integration**: How to configure the webhook.
4. **MT5 User Setup**: How to add the URL to `Tools > Options > Expert Advisors > Allow WebRequest`.
5. **Mobile Control Guide**: How to use the pending order comment trick on iOS/Android.
6. **Security Notes**: Why keys are hashed, how rate-limiting works, and the grace period logic.

## 4.2 `license-server/README.md`
Standard Go project README with build, run, and test instructions.

## 4.3 `presets/XAUUSD_M1_UltraScalp_Licensed.set`
Include the new license inputs. `InpLicenseKey` left blank, `InpLicenseGraceMinutes = 720`.

---

## ACCEPTANCE CRITERIA

**Go Backend**
- Compiles and passes basic routing tests.
- Docker images build successfully.
- PostgreSQL schema applies cleanly.
- Redis caching prevents DB hits on subsequent `heartbeat` calls.

**MQL5 Integration**
- If `InpLicenseKey == ""`, EA ignores license logic completely (zero overhead).
- `WebRequest` ONLY occurs in `OnTimer`, never in `OnTick` hot paths.
- EA gracefully survives server outage for `InpLicenseGraceMinutes` without stopping trades if previously validated.
- EA blocks new trades if server returns `valid: false`.
- Mobile commands delete the pending order and execute the state change immediately.
- Zero compile warnings.

**Security**
- License keys are SHA256 hashed in the PostgreSQL database.
- API enforces HTTPS.
- Rate limiting is active on public endpoints.
- Machine ID binds the license to the specific PC/VPS/Account.

## GUARDRAILS — DO NOT
- Do NOT call `WebRequest` inside `OnTick`.
- Do NOT store plain-text license keys in the PostgreSQL database.
- Do NOT remove or bypass the existing Predict-A-Trade capital protection breakers.
- Do NOT commit actual Stripe secrets or DB passwords to the repository.
- Do NOT create a native mobile app; use the MT5 pending order trick as specified.
