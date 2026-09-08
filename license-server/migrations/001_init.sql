-- Predict-A-Trade license server schema (prompt.md Phase 1.2)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS licenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    license_key_hash TEXT UNIQUE NOT NULL, -- SHA256 hex of the raw key; raw keys are NEVER stored
    status TEXT NOT NULL DEFAULT 'active', -- active | expired | revoked
    plan TEXT DEFAULT 'monthly',
    max_activations INT DEFAULT 2,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS activations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    license_id UUID REFERENCES licenses(id),
    machine_id TEXT NOT NULL,
    account_login BIGINT NOT NULL,
    broker_server TEXT NOT NULL,
    last_seen_at TIMESTAMPTZ DEFAULT NOW(),
    revoked BOOLEAN DEFAULT FALSE,
    UNIQUE(license_id, machine_id, account_login, broker_server)
);

CREATE TABLE IF NOT EXISTS license_settings (
    license_id UUID PRIMARY KEY REFERENCES licenses(id),
    auto_trading_enabled BOOLEAN DEFAULT TRUE,
    settings_json JSONB DEFAULT '{}',
    settings_version INT DEFAULT 1,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS license_events (
    id BIGSERIAL PRIMARY KEY,
    license_id UUID,
    event_type TEXT, -- activation | heartbeat | revoked | invalid_key | rate_limited
    ip_address TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_license_key_hash ON licenses(license_key_hash);
CREATE INDEX IF NOT EXISTS idx_activations_license ON activations(license_id);
CREATE INDEX IF NOT EXISTS idx_activations_last_seen ON activations(last_seen_at);
CREATE INDEX IF NOT EXISTS idx_license_events_license ON license_events(license_id);