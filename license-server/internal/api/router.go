// Package api assembles the HTTP router, middleware and handlers.
package api

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"predictatrade-license-server/internal/cache"
	"predictatrade-license-server/internal/config"
	"predictatrade-license-server/internal/db"
)

type Server struct {
	cfg   *config.Config
	store *db.Store
	cache *cache.Cache
}

func NewServer(cfg *config.Config, store *db.Store, cache *cache.Cache) *Server {
	return &Server{cfg: cfg, store: store, cache: cache}
}

func (s *Server) Router() *gin.Engine {
	if s.cfg.Env == "production" {
		gin.SetMode(gin.ReleaseMode)
	}
	r := gin.New()
	r.Use(gin.Logger(), gin.Recovery())
	r.RedirectTrailingSlash = true

	// Security headers
	r.Use(func(c *gin.Context) {
		c.Header("X-Content-Type-Options", "nosniff")
		c.Header("X-Frame-Options", "DENY")
		c.Header("Cache-Control", "no-store")
		c.Next()
	})

	// Production: reject plain HTTP (TLS terminates at the reverse proxy / LB).
	if s.cfg.Env == "production" {
		r.Use(func(c *gin.Context) {
			if c.Request.TLS == nil &&
				c.GetHeader("X-Forwarded-Proto") != "https" &&
				c.Request.RemoteAddr != "" &&
				c.Request.Header.Get("X-Healthcheck") == "" {
				c.AbortWithStatusJSON(http.StatusUpgradeRequired,
					gin.H{"error": "https required"})
				return
			}
			c.Next()
		})
	}

	v1 := r.Group("/v1")
	v1.Use(s.rateLimit)
	{
		v1.POST("/activate", s.handleActivate)
		v1.POST("/heartbeat", s.handleHeartbeat)
		v1.POST("/webhook/stripe", s.handleStripeWebhook)
	}
	r.GET("/healthz", func(c *gin.Context) {
		c.Header("X-Healthcheck", "1")
		c.JSON(http.StatusOK, gin.H{"ok": true, "ts": time.Now().Unix()})
	})
	return r
}