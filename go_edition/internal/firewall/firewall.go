// Package firewall provides firewall management functionality for the Zapret application.
// It supports both nftables and iptables backends with context-based operations
// and structured error handling.
package firewall

import (
	"context"
	"log/slog"
	"os/exec"

	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/errors"
	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/strategy"
)

const (
	// NFTablesBackendType is the nftables firewall backend
	NFTablesBackendType = "nftables"
	// IPTablesBackendType is the iptables firewall backend
	IPTablesBackendType = "iptables"
	// NFTTableName is the name of the nftables table
	NFTTableName = "inet zapretunix"
	// NFTCChainName is the name of the nftables chain
	NFTCChainName = "output"
	// NFTRuleComment is the comment added to nftables rules
	NFTRuleComment = "Added by zapret script"
	// IPTChainName is the name of the iptables chain
	IPTChainName = "ZAPRET_UNIX"
)

// Backend interface defines the methods that all firewall backends must implement
type Backend interface {
	SetupRules(ctx context.Context, rules []strategy.FirewallRule, iface string) error
	Cleanup(ctx context.Context) error
	Status(ctx context.Context) (BackendStatus, error)
	Type() string
}

// Manager manages firewall operations
type Manager struct {
	backend Backend
	iface   string
}

// BackendStatus represents the status of a firewall backend
type BackendStatus struct {
	Type      string
	Status    string
	RuleCount int
	Active    bool
}

// NewManager creates a new firewall manager with automatic backend detection
func NewManager(ctx context.Context, iface string) (*Manager, error) {
	select {
	case <-ctx.Done():
		return nil, errors.Wrap(ctx.Err(), "context canceled during firewall manager creation")
	default:
	}

	slog.Debug("Creating firewall manager", "interface", iface)

	// Detect available firewall backend
	backend, err := detectBackend(ctx)
	if err != nil {
		return nil, errors.Wrap(err, "failed to detect firewall backend")
	}

	slog.Debug("Detected firewall backend", "backend", backend.Type())

	return &Manager{
		backend: backend,
		iface:   iface,
	}, nil
}

func detectBackend(ctx context.Context) (Backend, error) {
	// Try nftables first
	if _, err := exec.LookPath("nft"); err == nil {
		if err := testNFTables(ctx); err == nil {
			return NewNFTablesBackend(), nil
		}
	}

	// Fall back to iptables
	if _, err := exec.LookPath("iptables"); err == nil {
		if err := testIPTables(ctx); err == nil {
			return NewIPTablesBackend(), nil
		}
	}

	return nil, errors.NewFirewallError("", "detection", "no supported firewall backend found (nftables/iptables)")
}

func testNFTables(ctx context.Context) error {
	cmd := exec.CommandContext(ctx, "nft", "list", "tables")
	return cmd.Run()
}

func testIPTables(ctx context.Context) error {
	cmd := exec.CommandContext(ctx, "iptables", "-L", "-n")
	return cmd.Run()
}

// SetupRules sets up firewall rules based on the parsed strategy
func (m *Manager) SetupRules(ctx context.Context, rules []strategy.FirewallRule) error {
	select {
	case <-ctx.Done():
		return errors.Wrap(ctx.Err(), "context canceled during firewall rule setup")
	default:
	}

	slog.Debug("Setting up firewall rules", "backend", m.backend.Type(), "interface", m.iface, "rules", len(rules))

	if err := m.backend.SetupRules(ctx, rules, m.iface); err != nil {
		return errors.Wrapf(err, "failed to setup rules with %s backend", m.backend.Type())
	}

	return nil
}

// Cleanup removes all firewall rules added by this application
func (m *Manager) Cleanup(ctx context.Context) error {
	select {
	case <-ctx.Done():
		return errors.Wrap(ctx.Err(), "context canceled during firewall cleanup")
	default:
	}

	slog.Debug("Cleaning up firewall rules", "backend", m.backend.Type())

	if err := m.backend.Cleanup(ctx); err != nil {
		return errors.Wrapf(err, "failed to cleanup rules with %s backend", m.backend.Type())
	}

	return nil
}

// Status returns the current status of the firewall backend
func (m *Manager) Status(ctx context.Context) (BackendStatus, error) {
	select {
	case <-ctx.Done():
		return BackendStatus{}, errors.Wrap(ctx.Err(), "context canceled during firewall status check")
	default:
	}

	status, err := m.backend.Status(ctx)
	if err != nil {
		return BackendStatus{}, errors.Wrapf(err, "failed to get status from %s backend", m.backend.Type())
	}

	return status, nil
}

// Type returns the firewall backend type
func (m *Manager) Type() string {
	return m.backend.Type()
}
