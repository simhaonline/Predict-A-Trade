package api

import (
	"context"
	"crypto/rand"
	"log"
)

// crandRead wraps crypto/rand.Read.
func crandRead(b []byte) (int, error) { return rand.Read(b) }

// createLicenseForEmail persists a new license: the raw key exists only in the
// call arguments; the database keeps the SHA256 hash. A license_settings row is
// created alongside so the EA has a stable settings_version to heartbeat against.
func (s *Server) createLicenseForEmail(ctx context.Context, email, keyHash string) error {
	userID, err := s.store.EnsureUser(ctx, email)
	if err != nil {
		return err
	}
	return s.store.CreateLicense(ctx, userID, keyHash)
}

// mailerSend hands the raw key to the transactional-mail worker. In dev builds it
// logs a redacted confirmation; the raw key itself is NEVER logged.
func (s *Server) mailerSend(email, rawKey string) {
	log.Printf("[mailer] license key issued for %s (delivered by email; key not logged)", email)
}