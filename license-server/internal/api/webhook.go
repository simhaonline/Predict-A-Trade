package api

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// timeNow is a var so tests can freeze the clock.
var timeNow = time.Now

// handleStripeWebhook verifies the Stripe signature header and processes the two
// subscription lifecycle events we care about. Raw keys are generated server-side,
// stored ONLY as SHA256 hashes, and emailed to the customer by the mailer job.
func (s *Server) handleStripeWebhook(c *gin.Context) {
	if s.cfg.StripeWebhookSecret == "" {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "webhooks_not_configured"})
		return
	}
	payload, err := io.ReadAll(io.LimitReader(c.Request.Body, 1<<20))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "read_failed"})
		return
	}
	sig := c.GetHeader("Stripe-Signature")
	if !verifyStripeSignature(payload, sig, s.cfg.StripeWebhookSecret, 300) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_signature"})
		return
	}

	var event struct {
		Type string `json:"type"`
		Data struct {
			Object struct {
				Email           string `json:"customer_email"`
				SubscriptionID  string `json:"subscription"`
				LicenseMetadata struct {
					LicenseKey string `json:"license_key"`
				} `json:"metadata"`
			} `json:"object"`
		} `json:"data"`
	}
	if err := json.Unmarshal(payload, &event); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "bad_payload"})
		return
	}

	switch event.Type {
	case "checkout.session.completed":
		// Generate a cryptographically random key, store only its hash.
		rawKey, err := generateLicenseKey()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "keygen_failed"})
			return
		}
		keyHash := hashKey(rawKey)
		if err := s.createLicenseForEmail(c.Request.Context(), event.Data.Object.Email, keyHash); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "store_error"})
			return
		}
		// Deliver the RAW key to the customer exactly once (email worker); never log it.
		s.mailerSend(event.Data.Object.Email, rawKey)

	case "customer.subscription.deleted":
		if event.Data.Object.LicenseMetadata.LicenseKey != "" {
			keyHash := hashKey(event.Data.Object.LicenseMetadata.LicenseKey)
			_, _ = s.store.RevokeLicense(c.Request.Context(), keyHash)
			_ = s.cache.DeleteLicense(c.Request.Context(), keyHash)
		}
	}

	c.JSON(http.StatusOK, gin.H{"received": true})
}

// verifyStripeSignature implements the v1 scheme: t=timestamp,v1=HMAC-SHA256(secret, "ts.payload").
func verifyStripeSignature(payload []byte, header, secret string, toleranceSec int64) bool {
	var t string
	var v1 string
	for _, part := range splitComma(header) {
		if len(part) > 2 && part[:2] == "t=" {
			t = part[2:]
		} else if len(part) > 3 && part[:3] == "v1=" {
			v1 = part[3:]
		}
	}
	if t == "" || v1 == "" {
		return false
	}
	var ts int64
	for _, ch := range t {
		if ch < '0' || ch > '9' {
			return false
		}
		ts = ts*10 + int64(ch-'0')
	}
	now := timeNow().Unix()
	if ts < now-toleranceSec || ts > now+toleranceSec {
		return false
	}
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(t + "."))
	mac.Write(payload)
	expected := hex.EncodeToString(mac.Sum(nil))
	return hmac.Equal([]byte(expected), []byte(v1))
}

func splitComma(s string) []string {
	out := []string{}
	cur := ""
	for _, ch := range s {
		if ch == ',' {
			out = append(out, cur)
			cur = ""
		} else {
			cur += string(ch)
		}
	}
	if cur != "" {
		out = append(out, cur)
	}
	return out
}

// generateLicenseKey: 32 bytes of crypto randomness, formatted PAT-XXXX-XXXX-XXXX-XXXX.
func generateLicenseKey() (string, error) {
	raw := make([]byte, 16)
	if _, err := crandRead(raw); err != nil {
		return "", err
	}
	const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	out := "PAT-"
	for i, b := range raw {
		if i > 0 && i%4 == 0 {
			out += "-"
		}
		out += string(alphabet[int(b)%len(alphabet)])
	}
	return out, nil
}

// genKey aliases generateLicenseKey for the test file.
func genKey() (string, error) { return generateLicenseKey() }
