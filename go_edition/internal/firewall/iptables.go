// Package firewall provides iptables backend implementation
package firewall

import (
	"context"
	"fmt"
	"log/slog"
	"os/exec"
	"strconv"
	"strings"

	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/errors"
	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/strategy"
)

// IPTablesBackend implements the Backend interface for iptables
type IPTablesBackend struct {
	// No additional fields needed for now
}

// NewIPTablesBackend creates a new iptables backend
func NewIPTablesBackend() *IPTablesBackend {
	return &IPTablesBackend{}
}

// Type returns the backend type
func (b *IPTablesBackend) Type() string {
	return IPTablesBackendType
}

// SetupRules sets up iptables rules
func (b *IPTablesBackend) SetupRules(ctx context.Context, rules []strategy.FirewallRule, iface string) error {
	select {
	case <-ctx.Done():
		return errors.Wrap(ctx.Err(), "context canceled during iptables rule setup")
	default:
	}

	slog.Debug("Setting up iptables rules", "interface", iface, "rules", len(rules))

	// Clean up existing rules first
	if err := b.cleanupExistingRules(ctx); err != nil {
		slog.Warn("Failed to cleanup existing iptables rules", "error", err)
	}

	// Create custom chain
	if err := b.createCustomChain(ctx); err != nil {
		return errors.Wrap(err, "failed to create iptables custom chain")
	}

	// Add rules to custom chain
	for _, rule := range rules {
		if err := b.addRuleToChain(ctx, rule, iface); err != nil {
			return errors.Wrapf(err, "failed to add rule: %s", rule.RawRule)
		}
	}

	// Attach custom chain to OUTPUT
	if err := b.attachChainToOutput(ctx); err != nil {
		return errors.Wrap(err, "failed to attach custom chain to OUTPUT")
	}

	return nil
}

func (b *IPTablesBackend) cleanupExistingRules(ctx context.Context) error {
	// Check if our custom chain exists
	if !b.chainExists(ctx) {
		return nil
	}

	// Remove the jump rule from OUTPUT chain
	b.removeJumpRuleFromOutput(ctx)

	// Flush our custom chain
	if err := b.flushCustomChain(ctx); err != nil {
		return errors.Wrap(err, "failed to flush custom chain")
	}

	// Delete our custom chain
	b.deleteCustomChain(ctx)

	return nil
}

func (b *IPTablesBackend) createCustomChain(ctx context.Context) error {
	cmd := exec.CommandContext(ctx, "iptables", "-N", IPTChainName)
	if err := cmd.Run(); err != nil {
		// If chain already exists, that's ok
		if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() == 1 {
			// Chain already exists, flush it
			if err := b.flushCustomChain(ctx); err != nil {
				return errors.Wrap(err, "failed to flush existing custom chain")
			}
			return nil
		}
		return errors.NewFirewallError(IPTablesBackendType, "create_chain", fmt.Sprintf("failed to create chain: %v", err))
	}
	return nil
}

func (b *IPTablesBackend) addRuleToChain(ctx context.Context, rule strategy.FirewallRule, iface string) error {
	// Parse ports and create individual rules for each port/range
	ports := parsePorts(rule.Ports)

	for _, port := range ports {
		cmdArgs := []string{"-A", IPTChainName}

		// Add interface if specified
		if iface != "" && iface != "any" {
			cmdArgs = append(cmdArgs, "-o", iface)
		}

		// Add protocol and port
		cmdArgs = append(cmdArgs, "-p", rule.Protocol, "--dport", port)

		// Add NFQUEUE target
		cmdArgs = append(cmdArgs, "-j", "NFQUEUE", "--queue-num", strconv.Itoa(rule.QueueNum))

		cmd := exec.CommandContext(ctx, "iptables", cmdArgs...)
		if err := cmd.Run(); err != nil {
			return errors.NewFirewallError(IPTablesBackendType, "add_rule",
				fmt.Sprintf("failed to add rule: %v (args: %v)", err, cmdArgs))
		}

		slog.Debug("Added iptables rule", "protocol", rule.Protocol, "port", port, "queue", rule.QueueNum)
	}

	return nil
}

func parsePorts(portsStr string) []string {
	// Remove curly braces if present
	portsStr = strings.Trim(portsStr, "{}")

	var ports []string
	portRanges := strings.Split(portsStr, ",")

	for _, pr := range portRanges {
		pr = strings.TrimSpace(pr)
		if pr == "" {
			continue
		}

		// Check if it's a range
		if strings.Contains(pr, "-") {
			parts := strings.Split(pr, "-")
			if len(parts) == 2 {
				start, err1 := strconv.Atoi(strings.TrimSpace(parts[0]))
				end, err2 := strconv.Atoi(strings.TrimSpace(parts[1]))

				if err1 == nil && err2 == nil && start <= end {
					ports = append(ports, fmt.Sprintf("%d:%d", start, end))
					continue
				}
			}
		}

		// Single port
		ports = append(ports, pr)
	}

	return ports
}

func (b *IPTablesBackend) attachChainToOutput(ctx context.Context) error {
	// Check if the rule already exists
	if b.jumpRuleExists(ctx) {
		return nil
	}

	cmd := exec.CommandContext(ctx, "iptables", "-A", "OUTPUT", "-j", IPTChainName)
	if err := cmd.Run(); err != nil {
		return errors.NewFirewallError(IPTablesBackendType, "attach_chain",
			fmt.Sprintf("failed to attach chain to OUTPUT: %v", err))
	}

	return nil
}

// Cleanup removes all iptables rules added by this application
func (b *IPTablesBackend) Cleanup(ctx context.Context) error {
	select {
	case <-ctx.Done():
		return errors.Wrap(ctx.Err(), "context canceled during iptables cleanup")
	default:
	}

	slog.Debug("Cleaning up iptables rules")
	return b.cleanupExistingRules(ctx)
}

// Status returns the current status of the iptables backend
func (b *IPTablesBackend) Status(ctx context.Context) (BackendStatus, error) {
	select {
	case <-ctx.Done():
		return BackendStatus{}, errors.Wrap(ctx.Err(), "context canceled during iptables status check")
	default:
	}

	status := BackendStatus{
		Type:   IPTablesBackendType,
		Status: "inactive",
	}

	if !b.chainExists(ctx) {
		status.Status = "no_chain"
		return status, nil
	}

	// Count rules in our custom chain
	ruleCount, err := b.countChainRules(ctx)
	if err != nil {
		return status, errors.Wrap(err, "failed to count chain rules for status")
	}

	status.RuleCount = ruleCount
	status.Status = "active"
	status.Active = true

	return status, nil
}

// Helper functions

func (b *IPTablesBackend) chainExists(ctx context.Context) bool {
	cmd := exec.CommandContext(ctx, "iptables", "-L", IPTChainName, "-n")
	return cmd.Run() == nil
}

func (b *IPTablesBackend) flushCustomChain(ctx context.Context) error {
	cmd := exec.CommandContext(ctx, "iptables", "-F", IPTChainName)
	return cmd.Run()
}

func (b *IPTablesBackend) deleteCustomChain(ctx context.Context) {
	cmd := exec.CommandContext(ctx, "iptables", "-X", IPTChainName)
	cmd.Run() // Ignore error if chain doesn't exist
}

func (b *IPTablesBackend) removeJumpRuleFromOutput(ctx context.Context) {
	// Find and remove the jump rule
	cmd := exec.CommandContext(ctx, "iptables", "-D", "OUTPUT", "-j", IPTChainName)
	cmd.Run() // Ignore error if rule doesn't exist
}

func (b *IPTablesBackend) jumpRuleExists(ctx context.Context) bool {
	cmd := exec.CommandContext(ctx, "iptables", "-L", "OUTPUT", "-n", "--line-numbers")
	output, err := cmd.Output()
	if err != nil {
		return false
	}

	return strings.Contains(string(output), "jump") && strings.Contains(string(output), IPTChainName)
}

func (b *IPTablesBackend) countChainRules(ctx context.Context) (int, error) {
	cmd := exec.CommandContext(ctx, "iptables", "-L", IPTChainName, "-n", "--line-numbers")
	output, err := cmd.Output()
	if err != nil {
		return 0, errors.NewFirewallError(IPTablesBackendType, "count_rules",
			fmt.Sprintf("failed to list chain rules: %v", err))
	}

	lines := strings.Split(string(output), "\n")
	// Subtract 2 for header and empty line
	count := len(lines) - 2
	if count < 0 {
		count = 0
	}

	return count, nil
}
