// Package config loads server configuration from the environment (or .env).
// NEVER hardcode secrets; everything comes from env vars documented in .env.example.
package config

import (
	"log"
	"os"
	"strconv"

	"github.com/joho/godotenv"
)

type Config struct {
	Port            string // HTTP listen port (behind TLS terminator or local dev)
	DatabaseURL     string // postgres://user:pass@host:5432/db
	RedisURL        string // redis://host:6379
	StripeSecretKey string // sk_live_ / sk_test_ (webhook signing secret lives apart)
	StripeWebhookSecret string
	Env             string // "production" enforces HTTPS behaviour
	HeartbeatCacheTTLSeconds  int
	ActivationCacheTTLSeconds int
	RateLimitPerMinIP    int
	RateLimitPerMinKey   int
}

func Load() *Config {
	_ = godotenv.Load() // optional .env in working dir

	c := &Config{
		Port:            getEnv("PORT", "8080"),
		DatabaseURL:     getEnv("DATABASE_URL", ""),
		RedisURL:        getEnv("REDIS_URL", "redis://localhost:6379"),
		StripeSecretKey: getEnv("STRIPE_SECRET_KEY", ""),
		StripeWebhookSecret: getEnv("STRIPE_WEBHOOK_SECRET", ""),
		Env:             getEnv("APP_ENV", "production"),
	}
	c.HeartbeatCacheTTLSeconds = getInt("HEARTBEAT_CACHE_TTL", 60)
	c.ActivationCacheTTLSeconds = getInt("ACTIVATION_CACHE_TTL", 3600)
	c.RateLimitPerMinIP = getInt("RATE_LIMIT_IP_PER_MIN", 10)
	c.RateLimitPerMinKey = getInt("RATE_LIMIT_KEY_PER_MIN", 30)
	if c.DatabaseURL == "" {
		log.Fatal("DATABASE_URL is required (see .env.example)")
	}
	return c
}

func getEnv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func getInt(k string, def int) int {
	if v := os.Getenv(k); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
		log.Printf("config: invalid int for %s (%q), using %d", k, v, def)
	}
	return def
}