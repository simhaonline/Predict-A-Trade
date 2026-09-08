// Package models defines the license domain types shared by handlers and store.
package models

import "time"

type License struct {
	ID              string
	UserID          *string
	Status          string // active | expired | revoked
	Plan            string
	MaxActivations  int
	ExpiresAt       time.Time
}

type Activation struct {
	LicenseID    string
	MachineID    string
	AccountLogin int64
	BrokerServer string
	LastSeenAt   time.Time
	Revoked      bool
}

type LicenseSettings struct {
	AutoTradingEnabled bool
	SettingsVersion    int
	SettingsJSON       string
}

// CachedLicense is the compact state stored in Redis (JSON-serialized).
type CachedLicense struct {
	Valid              bool   `json:"valid"`
	Reason             string `json:"reason,omitempty"`
	AutoTradingEnabled bool   `json:"auto_trading_enabled"`
	SettingsVersion    int    `json:"settings_version"`
	MaxActivations     int    `json:"max_activations"`
}