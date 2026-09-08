// Package cache wraps Redis: license state cache, rate-limit counters.
// Redis is the hot path; PostgreSQL is hit only on cache misses.
package cache

import (
	"context"
	"encoding/json"
	"time"

	"github.com/gomodule/redigo/redis"

	"predictatrade-license-server/internal/models"
)

type Cache struct {
	pool *redis.Pool
}

func New(redisURL string) *Cache {
	return &Cache{pool: &redis.Pool{
		MaxActive:   64,
		MaxIdle:     16,
		IdleTimeout: 90 * time.Second,
		Dial: func() (redis.Conn, error) {
			return redis.DialURL(redisURL, redis.DialConnectTimeout(3*time.Second))
		},
	}}
}

func (c *Cache) Close() error { return c.pool.Close() }

func licenseKey(keyHash string) string { return "lic:" + keyHash }

// GetLicense returns cached validation state; miss -> nil, nil.
func (c *Cache) GetLicense(ctx context.Context, keyHash string) (*models.CachedLicense, error) {
	conn, err := c.pool.GetContext(ctx)
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	reply, err := redis.String(conn.Do("GET", licenseKey(keyHash)))
	if err == redis.ErrNil {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var cl models.CachedLicense
	if err := json.Unmarshal([]byte(reply), &cl); err != nil {
		return nil, err
	}
	return &cl, nil
}

func (c *Cache) SetLicense(ctx context.Context, keyHash string, cl *models.CachedLicense, ttlSeconds int) error {
	blob, err := json.Marshal(cl)
	if err != nil {
		return err
	}
	conn, err := c.pool.GetContext(ctx)
	if err != nil {
		return err
	}
	defer conn.Close()
	_, err = conn.Do("SET", licenseKey(keyHash), string(blob), "EX", ttlSeconds)
	return err
}

func (c *Cache) DeleteLicense(ctx context.Context, keyHash string) error {
	conn, err := c.pool.GetContext(ctx)
	if err != nil {
		return err
	}
	defer conn.Close()
	_, err = conn.Do("DEL", licenseKey(keyHash))
	return err
}

// RateLimit allows `limit` requests per minute for the bucket; returns ok + remaining.
func (c *Cache) RateLimit(ctx context.Context, bucket string, limit int) (bool, int, error) {
	conn, err := c.pool.GetContext(ctx)
	if err != nil {
		return true, limit, err // fail-open: Redis outage must not block validations
	}
	defer conn.Close()
	key := "rl:" + bucket
	deadline := time.Now().Add(time.Minute).Unix()
	const script = `
	local n = redis.call('INCR', KEYS[1])
	if n == 1 then redis.call('EXPIREAT', KEYS[1], ARGV[1]) end
	return n`
	n, err := redis.Int(conn.Do("EVAL", script, 1, key, deadline))
	if err != nil {
		return true, limit, err
	}
	return n <= limit, limit - n, nil
}