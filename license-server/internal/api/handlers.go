package api

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"net/http"

	"github.com/gin-gonic/gin"

	"predictatrade-license-server/internal/models"
)

// rateLimit: 10 req/min per IP and 30 req/min per license key (Redis counters).
// Fail-open on Redis errors so an outage cannot take validation down with it.
func (s *Server) rateLimit(c *gin.Context) {
	ip := c.ClientIP()
	if ok, remaining, _ := s.cache.RateLimit(c.Request.Context(), "ip:"+ip, s.cfg.RateLimitPerMinIP); !ok {
		s.store.LogEvent(c.Request.Context(), nil, "rate_limited", ip)
		c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{"error": "rate_limited", "retry_after_sec": 60})
		return
	} else {
		c.Header("X-RateLimit-Remaining", itoa(remaining))
	}

	// Per-key limiting only applies once we can read the key from the body binding.
	// The handlers call s.rateLimitKey after binding.
	c.Next()
}

func itoa(n int) string {
	if n < 0 {
		n = 0
	}
	digits := []byte{}
	if n == 0 {
		return "0"
	}
	for n > 0 {
		digits = append([]byte{byte('0' + n%10)}, digits...)
		n /= 10
	}
	return string(digits)
}

// rateLimitKey enforces the per-license-key budget; called after body binding.
func (s *Server) rateLimitKey(c *gin.Context, keyHash string) bool {
	ok, _, _ := s.cache.RateLimit(c.Request.Context(), "key:"+keyHash, s.cfg.RateLimitPerMinKey)
	if !ok {
		s.store.LogEvent(c.Request.Context(), nil, "rate_limited", c.ClientIP())
		c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{"error": "rate_limited_key", "retry_after_sec": 60})
	}
	return ok
}

func hashKey(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}

func clientErr(c *gin.Context, code int, reason string) {
	c.JSON(code, gin.H{"valid": false, "reason": reason})
}

// ---- request bodies --------------------------------------------------------

type activateReq struct {
	LicenseKey   string `json:"license_key" binding:"required"`
	MachineID    string `json:"machine_id" binding:"required"`
	AccountLogin int64  `json:"account_login" binding:"required"`
	BrokerServer string `json:"broker_server" binding:"required"`
}

type heartbeatReq struct {
	LicenseKey      string `json:"license_key" binding:"required"`
	MachineID       string `json:"machine_id" binding:"required"`
	AccountLogin    int64  `json:"account_login" binding:"required"`
	BrokerServer    string `json:"broker_server"`
	SettingsVersion int    `json:"settings_version"`
}

// ---- handlers --------------------------------------------------------------

func (s *Server) handleActivate(c *gin.Context) {
	var req activateReq
	if err := c.ShouldBindJSON(&req); err != nil {
		clientErr(c, http.StatusBadRequest, "bad_request")
		return
	}
	keyHash := hashKey(req.LicenseKey)
	if !s.rateLimitKey(c, keyHash) {
		return
	}
	ctx := c.Request.Context()

	// 1. cache first
	if cached, err := s.cache.GetLicense(ctx, keyHash); err == nil && cached != nil && cached.Valid {
		if err := s.store.UpsertActivation(ctx, models.Activation{
			LicenseID: s.licenseIDForHash(ctx, keyHash), MachineID: req.MachineID,
			AccountLogin: req.AccountLogin, BrokerServer: req.BrokerServer,
		}); err == nil {
			c.JSON(http.StatusOK, gin.H{"valid": true, "auto_trading_enabled": cached.AutoTradingEnabled, "settings_version": cached.SettingsVersion})
			return
		}
	}

	// 2. database
	license, err := s.store.LicenseByKeyHash(ctx, keyHash)
	if err != nil {
		s.store.LogEvent(ctx, nil, "invalid_key", c.ClientIP())
		clientErr(c, http.StatusOK, "invalid_key")
		return
	}
	if license.Status != "active" || time_Expired(license) {
		cl := &models.CachedLicense{Valid: false, Reason: "expired_or_revoked"}
		_ = s.cache.SetLicense(ctx, keyHash, cl, s.cfg.ActivationCacheTTLSeconds)
		clientErr(c, http.StatusOK, "expired_or_revoked")
		return
	}
	count, err := s.store.CountActivations(ctx, license.ID)
	if err != nil {
		clientErr(c, http.StatusInternalServerError, "store_error")
		return
	}
	if count >= license.MaxActivations {
		exists, _ := s.store.ActivationExists(ctx, license.ID, req.MachineID, req.AccountLogin, req.BrokerServer)
		if !exists {
			s.store.LogEvent(ctx, &license.ID, "activation_limit", c.ClientIP())
			clientErr(c, http.StatusOK, "max_activations_reached")
			return
		}
	}
	if err := s.store.UpsertActivation(ctx, models.Activation{
		LicenseID: license.ID, MachineID: req.MachineID,
		AccountLogin: req.AccountLogin, BrokerServer: req.BrokerServer,
	}); err != nil {
		clientErr(c, http.StatusInternalServerError, "store_error")
		return
	}
	st, _ := s.store.Settings(ctx, license.ID)
	cl := &models.CachedLicense{
		Valid: true, AutoTradingEnabled: st != nil && st.AutoTradingEnabled,
		SettingsVersion: settingsVersion(st), MaxActivations: license.MaxActivations,
	}
	_ = s.cache.SetLicense(ctx, keyHash, cl, s.cfg.ActivationCacheTTLSeconds)
	s.store.LogEvent(ctx, &license.ID, "activation", c.ClientIP())
	c.JSON(http.StatusOK, gin.H{"valid": true, "auto_trading_enabled": cl.AutoTradingEnabled, "settings_version": cl.SettingsVersion})
}

func (s *Server) handleHeartbeat(c *gin.Context) {
	var req heartbeatReq
	if err := c.ShouldBindJSON(&req); err != nil {
		clientErr(c, http.StatusBadRequest, "bad_request")
		return
	}
	keyHash := hashKey(req.LicenseKey)
	if !s.rateLimitKey(c, keyHash) {
		return
	}
	ctx := c.Request.Context()

	if cached, err := s.cache.GetLicense(ctx, keyHash); err == nil && cached != nil {
		if !cached.Valid {
			clientErr(c, http.StatusOK, cached.Reason)
			return
		}
		if _, err := s.store.TouchActivation(ctx, s.licenseIDForHash(ctx, keyHash), req.MachineID, req.AccountLogin, req.BrokerServer); err == nil {
			c.JSON(http.StatusOK, gin.H{"valid": true, "auto_trading_enabled": cached.AutoTradingEnabled, "settings_version": cached.SettingsVersion})
			return
		}
	}

	license, err := s.store.LicenseByKeyHash(ctx, keyHash)
	if err != nil {
		s.store.LogEvent(ctx, nil, "invalid_key", c.ClientIP())
		clientErr(c, http.StatusOK, "invalid_key")
		return
	}
	if license.Status != "active" || time_Expired(license) {
		cl := &models.CachedLicense{Valid: false, Reason: "expired_or_revoked"}
		_ = s.cache.SetLicense(ctx, keyHash, cl, s.cfg.HeartbeatCacheTTLSeconds)
		clientErr(c, http.StatusOK, "expired_or_revoked")
		return
	}
	ok, err := s.store.ActivationExists(ctx, license.ID, req.MachineID, req.AccountLogin, req.BrokerServer)
	if err != nil {
		clientErr(c, http.StatusInternalServerError, "store_error")
		return
	}
	if !ok {
		// heartbeats never create seats; the machine must activate first
		clientErr(c, http.StatusOK, "not_activated")
		return
	}
	if _, err := s.store.TouchActivation(ctx, license.ID, req.MachineID, req.AccountLogin, req.BrokerServer); err != nil {
		// non-fatal: validation can still succeed
		_ = err
	}
	st, _ := s.store.Settings(ctx, license.ID)
	cl := &models.CachedLicense{
		Valid: true, AutoTradingEnabled: st == nil || st.AutoTradingEnabled,
		SettingsVersion: settingsVersion(st), MaxActivations: license.MaxActivations,
	}
	_ = s.cache.SetLicense(ctx, keyHash, cl, s.cfg.HeartbeatCacheTTLSeconds)
	s.store.LogEvent(ctx, &license.ID, "heartbeat", c.ClientIP())
	c.JSON(http.StatusOK, gin.H{"valid": true, "auto_trading_enabled": cl.AutoTradingEnabled, "settings_version": cl.SettingsVersion})
}

// ---- helpers ---------------------------------------------------------------

func time_Expired(l *models.License) bool {
	return !l.ExpiresAt.After(timeNow())
}

func settingsVersion(st *models.LicenseSettings) int {
	if st == nil {
		return 1
	}
	return st.SettingsVersion
}

// licenseIDForHash resolves the license UUID from cache-miss paths cheaply.
func (s *Server) licenseIDForHash(ctx context.Context, keyHash string) string {
	l, err := s.store.LicenseByKeyHash(ctx, keyHash)
	if err != nil {
		return ""
	}
	return l.ID
}