package api

// Routing smoke test: no external services — handlers that need the store are not
// reached; we verify route registration, security headers, HTTPS enforcement and
// 400-on-malformed-body paths.

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"predictatrade-license-server/internal/cache"
	"predictatrade-license-server/internal/config"
	"predictatrade-license-server/internal/db"
)

func devCfg() *config.Config {
	return &config.Config{
		Port: "0", DatabaseURL: "postgres://test", RedisURL: "redis://test",
		Env: "development", RateLimitPerMinIP: 10, RateLimitPerMinKey: 30,
		ActivationCacheTTLSeconds: 60, HeartbeatCacheTTLSeconds: 60,
	}
}

func TestRoutesRespond(t *testing.T) {
	cfg := devCfg()
	// nil store/cache is safe for paths that abort before touching them
	srv := NewServer(cfg, &db.Store{}, cache.New("redis://localhost:6399"))
	r := srv.Router()

	cases := []struct {
		name, method, path, body string
		want                     int
	}{
		{"healthz", "GET", "/healthz", "", http.StatusOK},
		{"activate bad json", "POST", "/v1/activate", `{"nope`, http.StatusBadRequest},
		{"heartbeat bad json", "POST", "/v1/heartbeat", `not-json`, http.StatusBadRequest},
		{"activate missing fields", "POST", "/v1/activate", `{}`, http.StatusBadRequest},
		{"heartbeat missing fields", "POST", "/v1/heartbeat", `{}`, http.StatusBadRequest},
	}
	for _, tc := range cases {
		w := httptest.NewRecorder()
		req := httptest.NewRequest(tc.method, tc.path, strings.NewReader(tc.body))
		req.Header.Set("Content-Type", "application/json")
		r.ServeHTTP(w, req)
		if w.Code != tc.want {
			t.Errorf("%s: got %d want %d", tc.name, w.Code, tc.want)
		}
	}
}

func TestHTTPSRejectedInProduction(t *testing.T) {
	cfg := devCfg()
	cfg.Env = "production"
	srv := NewServer(cfg, &db.Store{}, cache.New("redis://localhost:6399"))
	r := srv.Router()
	w := httptest.NewRecorder()
	req := httptest.NewRequest("GET", "/healthz", nil) // plain HTTP on production
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUpgradeRequired {
		t.Errorf("plain HTTP in production: got %d want %d", w.Code, http.StatusUpgradeRequired)
	}
	// with X-Forwarded-Proto=https it must pass through
	w2 := httptest.NewRecorder()
	req2 := httptest.NewRequest("GET", "/healthz", nil)
	req2.Header.Set("X-Forwarded-Proto", "https")
	req2.Header.Set("X-Healthcheck", "1")
	r.ServeHTTP(w2, req2)
	if w2.Code != http.StatusOK {
		t.Errorf("TLS-proxied healthz: got %d want %d", w2.Code, http.StatusOK)
	}
}

func TestSecurityHeaders(t *testing.T) {
	cfg := devCfg()
	srv := NewServer(cfg, &db.Store{}, cache.New("redis://localhost:6399"))
	r := srv.Router()
	w := httptest.NewRecorder()
	req := httptest.NewRequest("GET", "/healthz", nil)
	req.Header.Set("X-Healthcheck", "1")
	r.ServeHTTP(w, req)
	if w.Header().Get("X-Content-Type-Options") != "nosniff" {
		t.Error("missing X-Content-Type-Options")
	}
}

func TestLicenseKeyFormat(t *testing.T) {
	// generateLicenseKey is in package api; smoke-check the alphabet/shape via webhook helper
	// (direct call since the test lives in the same package tree)
	key, err := genKey()
	if err != nil {
		t.Fatal(err)
	}
	if len(key) != len("PAT-XXXX-XXXX-XXXX-XXXX") || key[:4] != "PAT-" {
		t.Errorf("unexpected key format %q", key)
	}
}