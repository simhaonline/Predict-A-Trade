// Package db provides the PostgreSQL store. All access is parameterized; the raw
// license key never touches the database — only its SHA256 hex hash.
package db

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"predictatrade-license-server/internal/models"
)

type Store struct {
	Pool *pgxpool.Pool
}

func New(ctx context.Context, databaseURL string) (*Store, error) {
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return nil, err
	}
	if err := pool.Ping(ctx); err != nil {
		return nil, err
	}
	return &Store{Pool: pool}, nil
}

func (s *Store) Close() { s.Pool.Close() }

// LicenseByKeyHash resolves a license by SHA256(key) hex hash.
func (s *Store) LicenseByKeyHash(ctx context.Context, keyHash string) (*models.License, error) {
	row := s.Pool.QueryRow(ctx,
		`SELECT id, user_id, status, COALESCE(plan,'monthly'), max_activations, expires_at
		 FROM licenses WHERE license_key_hash = $1`, keyHash)
	var l models.License
	var userID *string
	if err := row.Scan(&l.ID, &userID, &l.Status, &l.Plan, &l.MaxActivations, &l.ExpiresAt); err != nil {
		return nil, err
	}
	l.UserID = userID
	return &l, nil
}

func (s *Store) CountActivations(ctx context.Context, licenseID string) (int, error) {
	var n int
	err := s.Pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM activations WHERE license_id=$1 AND revoked=false`, licenseID).Scan(&n)
	return n, err
}

// UpsertActivation inserts or refreshes the (license, machine, account, broker) seat.
func (s *Store) UpsertActivation(ctx context.Context, a models.Activation) error {
	_, err := s.Pool.Exec(ctx,
		`INSERT INTO activations (license_id, machine_id, account_login, broker_server, last_seen_at)
		 VALUES ($1,$2,$3,$4,NOW())
		 ON CONFLICT (license_id, machine_id, account_login, broker_server)
		 DO UPDATE SET last_seen_at = NOW(), revoked = false`,
		a.LicenseID, a.MachineID, a.AccountLogin, a.BrokerServer)
	return err
}

// TouchActivation throttles heartbeat writes: only update last_seen_at when stale.
func (s *Store) TouchActivation(ctx context.Context, licenseID, machineID string, accountLogin int64, brokerServer string) (bool, error) {
	tag, err := s.Pool.Exec(ctx,
		`UPDATE activations SET last_seen_at = NOW()
		 WHERE license_id=$1 AND machine_id=$2 AND account_login=$3 AND broker_server=$4
		   AND last_seen_at < NOW() - INTERVAL '1 hour'`,
		licenseID, machineID, accountLogin, brokerServer)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}

func (s *Store) ActivationExists(ctx context.Context, licenseID, machineID string, accountLogin int64, brokerServer string) (bool, error) {
	var ok bool
	err := s.Pool.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM activations
		  WHERE license_id=$1 AND machine_id=$2 AND account_login=$3 AND broker_server=$4 AND revoked=false)`,
		licenseID, machineID, accountLogin, brokerServer).Scan(&ok)
	return ok, err
}

func (s *Store) Settings(ctx context.Context, licenseID string) (*models.LicenseSettings, error) {
	row := s.Pool.QueryRow(ctx,
		`SELECT auto_trading_enabled, settings_version, COALESCE(settings_json::text,'{}')
		 FROM license_settings WHERE license_id=$1`, licenseID)
	var st models.LicenseSettings
	if err := row.Scan(&st.AutoTradingEnabled, &st.SettingsVersion, &st.SettingsJSON); err != nil {
		return nil, err
	}
	return &st, nil
}

func (s *Store) LogEvent(ctx context.Context, licenseID *string, eventType, ip string) {
	if licenseID != nil {
		_, _ = s.Pool.Exec(ctx,
			`INSERT INTO license_events (license_id, event_type, ip_address) VALUES ($1,$2,$3)`,
			*licenseID, eventType, ip)
		return
	}
	_, _ = s.Pool.Exec(ctx,
		`INSERT INTO license_events (event_type, ip_address) VALUES ($1,$2)`, eventType, ip)
}

// RevokeLicense flips status and drops the Redis cache entry; used by the Stripe webhook.
func (s *Store) RevokeLicense(ctx context.Context, keyHash string) (bool, error) {
	tag, err := s.Pool.Exec(ctx,
		`UPDATE licenses SET status='revoked' WHERE license_key_hash=$1`, keyHash)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}

var _ = time.Now // keep time imported for future use in this file