package db

import (
	"context"

	"predictatrade-license-server/internal/models"
)

// EnsureUser upserts a user by email and returns the id.
func (s *Store) EnsureUser(ctx context.Context, email string) (string, error) {
	var id string
	err := s.Pool.QueryRow(ctx,
		`INSERT INTO users (email) VALUES ($1)
		 ON CONFLICT (email) DO UPDATE SET email = EXCLUDED.email
		 RETURNING id`, email).Scan(&id)
	return id, err
}

// CreateLicense inserts the license row (hash only) with a 30-day monthly window
// and its default settings row.
func (s *Store) CreateLicense(ctx context.Context, userID, keyHash string) error {
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(context.Background())

	var licenseID string
	if err := tx.QueryRow(ctx,
		`INSERT INTO licenses (user_id, license_key_hash, status, plan, max_activations, expires_at)
		 VALUES ($1,$2,'active','monthly',2, NOW() + INTERVAL '30 days')
		 RETURNING id`, userID, keyHash).Scan(&licenseID); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx,
		`INSERT INTO license_settings (license_id, auto_trading_enabled, settings_json, settings_version)
		 VALUES ($1, true, '{}', 1) ON CONFLICT (license_id) DO NOTHING`, licenseID); err != nil {
		return err
	}
	return tx.Commit(context.Background())
}

var _ = models.License{} // keep models import for future expansions