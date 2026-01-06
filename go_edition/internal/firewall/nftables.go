// Package firewall provides nftables backend implementation
package firewall

import (
	"context"
	"fmt"
	"log/slog"
	"os/exec"
	"strings"

	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/errors"
	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/strategy"
)

// NFTablesBackend implements the Backend interface for nftables
type NFTablesBackend struct {
	// No additional fields needed for now
}

// NewNFTablesBackend creates a new nftables backend
func NewNFTablesBackend() *NFTablesBackend {
	return &NFTablesBackend{}
}

// Type returns the backend type
func (b *NFTablesBackend) Type() string {
	return NFTablesBackendType
}

// SetupRules sets up nftables rules
func (b *NFTablesBackend) SetupRules(ctx context.Context, rules []strategy.FirewallRule, iface string) error {
	select {
	case <-ctx.Done():
		return errors.Wrap(ctx.Err(), "context canceled during nftables rule setup")
	default:
	}

	slog.Debug("Setting up nftables rules", "interface", iface, "rules", len(rules))

	// Clean up existing rules first
	if err := b.cleanupExistingRules(ctx); err != nil {
		slog.Warn("Failed to cleanup existing nftables rules", "error", err)
	}

	// Create table and chain
	if err := b.createTableAndChain(ctx); err != nil {
		return errors.Wrap(err, "failed to create nftables table and chain")
	}

	// Add rules
	for _, rule := range rules {
		if err := b.addRule(ctx, rule, iface); err != nil {
			return errors.Wrapf(err, "failed to add rule: %s", rule.RawRule)
		}
	}

	return nil
}

func (b *NFTablesBackend) cleanupExistingRules(ctx context.Context) error {
	// Check if table exists
	if !b.tableExists(ctx) {
		return nil
	}

	// Check if chain exists
	if !b.chainExists(ctx) {
		return nil
	}

	// Get all rule handles with our comment
	handles, err := b.getRuleHandlesWithComment(ctx)
	if err != nil {
		return errors.Wrap(err, "failed to get rule handles")
	}

	// Delete rules by handle
	for _, handle := range handles {
		if err := b.deleteRuleByHandle(ctx, handle); err != nil {
			slog.Warn("Failed to delete nftables rule", "error", err, "handle", handle)
		}
	}

	// Delete chain and table if they're empty
	b.deleteChainIfEmpty(ctx)
	b.deleteTableIfEmpty(ctx)

	return nil
}

func (b *NFTablesBackend) createTableAndChain(ctx context.Context) error {
	// Create table
	cmd := exec.CommandContext(ctx, "nft", "add", "table", NFTTableName)
	if err := cmd.Run(); err != nil {
		return errors.NewFirewallError(NFTablesBackendType, "create_table", fmt.Sprintf("failed to create table: %v", err))
	}

	// Create chain
	chainCmd := fmt.Sprintf("add chain %s %s { type filter hook output priority 0; }", NFTTableName, NFTCChainName)
	cmd = exec.CommandContext(ctx, "nft", strings.Split(chainCmd, " ")...)
	if err := cmd.Run(); err != nil {
		return errors.NewFirewallError(NFTablesBackendType, "create_chain", fmt.Sprintf("failed to create chain: %v", err))
	}

	return nil
}

func (b *NFTablesBackend) addRule(ctx context.Context, rule strategy.FirewallRule, iface string) error {
	oifClause := ""
	if iface != "" && iface != "any" {
		oifClause = fmt.Sprintf("oifname \"%s\" ", iface)
	}

	// Build the nftables rule command
	ruleCmd := fmt.Sprintf("add rule %s %s %s%s counter queue num %d bypass comment \"%s\"",
		NFTTableName, NFTCChainName, oifClause, rule.RawRule, rule.QueueNum, NFTRuleComment)

	cmd := exec.CommandContext(ctx, "nft", strings.Split(ruleCmd, " ")...)
	if err := cmd.Run(); err != nil {
		return errors.NewFirewallError(NFTablesBackendType, "add_rule",
			fmt.Sprintf("failed to add rule: %v (command: %s)", err, ruleCmd))
	}

	slog.Debug("Added nftables rule", "protocol", rule.Protocol, "ports", rule.Ports, "queue", rule.QueueNum)

	return nil
}

// Cleanup removes all nftables rules added by this application
func (b *NFTablesBackend) Cleanup(ctx context.Context) error {
	select {
	case <-ctx.Done():
		return errors.Wrap(ctx.Err(), "context canceled during nftables cleanup")
	default:
	}

	slog.Debug("Cleaning up nftables rules")
	return b.cleanupExistingRules(ctx)
}

// Status returns the current status of the nftables backend
func (b *NFTablesBackend) Status(ctx context.Context) (BackendStatus, error) {
	select {
	case <-ctx.Done():
		return BackendStatus{}, errors.Wrap(ctx.Err(), "context canceled during nftables status check")
	default:
	}

	status := BackendStatus{
		Type:   NFTablesBackendType,
		Status: "inactive",
	}

	if !b.tableExists(ctx) {
		status.Status = "no_table"
		return status, nil
	}

	if !b.chainExists(ctx) {
		status.Status = "no_chain"
		return status, nil
	}

	handles, err := b.getRuleHandlesWithComment(ctx)
	if err != nil {
		return status, errors.Wrap(err, "failed to get rule handles for status")
	}

	status.RuleCount = len(handles)
	status.Status = "active"
	status.Active = true

	return status, nil
}

// Helper functions

func (b *NFTablesBackend) tableExists(ctx context.Context) bool {
	cmd := exec.CommandContext(ctx, "nft", "list", "tables")
	output, err := cmd.Output()
	if err != nil {
		return false
	}
	return strings.Contains(string(output), NFTTableName)
}

func (b *NFTablesBackend) chainExists(ctx context.Context) bool {
	cmd := exec.CommandContext(ctx, "nft", "list", "chain", NFTTableName, NFTCChainName)
	return cmd.Run() == nil
}

func (b *NFTablesBackend) getRuleHandlesWithComment(ctx context.Context) ([]string, error) {
	cmd := exec.CommandContext(ctx, "nft", "-a", "list", "chain", NFTTableName, NFTCChainName)
	output, err := cmd.Output()
	if err != nil {
		return nil, errors.NewFirewallError(NFTablesBackendType, "get_rules", fmt.Sprintf("failed to list rules: %v", err))
	}

	var handles []string
	lines := strings.Split(string(output), "\n")

	for _, line := range lines {
		if strings.Contains(line, NFTRuleComment) {
			// Extract handle (last field)
			fields := strings.Fields(line)
			if len(fields) > 0 {
				handles = append(handles, fields[len(fields)-1])
			}
		}
	}

	return handles, nil
}

func (b *NFTablesBackend) deleteRuleByHandle(ctx context.Context, handle string) error {
	cmd := exec.CommandContext(ctx, "nft", "delete", "rule", NFTTableName, NFTCChainName, "handle", handle)
	return cmd.Run()
}

func (b *NFTablesBackend) deleteChainIfEmpty(ctx context.Context) {
	cmd := exec.CommandContext(ctx, "nft", "delete", "chain", NFTTableName, NFTCChainName)
	cmd.Run() // Ignore error if chain doesn't exist or isn't empty
}

func (b *NFTablesBackend) deleteTableIfEmpty(ctx context.Context) {
	cmd := exec.CommandContext(ctx, "nft", "delete", "table", NFTTableName)
	cmd.Run() // Ignore error if table doesn't exist or isn't empty
}
