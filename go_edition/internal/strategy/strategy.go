// Package strategy provides parsing and processing of strategy files
// for the Zapret application. It uses generics for flexible rule processing
// and supports template variables and GameFilter substitutions.
package strategy

import (
	"bufio"
	"context"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/errors"
)

const (
	// GameFilterPorts are the default ports used for GameFilter
	GameFilterPorts = "1024-65535"
	// BinPlaceholder is the placeholder for binary directory
	BinPlaceholder = "%BIN%"
	// ListsPlaceholder is the placeholder for lists directory
	ListsPlaceholder = "%LISTS%"
	// GameFilterPlaceholder is the placeholder for GameFilter ports
	GameFilterPlaceholder = "%GameFilter%"
)

// FirewallRule represents a firewall rule to be applied
type FirewallRule struct {
	Protocol string
	Ports    string
	QueueNum int
	Bypass   bool
	RawRule  string
}

// NFQWSParams represents parameters for nfqws process
type NFQWSParams struct {
	QueueNum int
	Args     []string
}

// Strategy contains parsed strategy information
type Strategy struct {
	FirewallRules []FirewallRule
	NFQWSParams   []NFQWSParams
	RawLines      []string
}

// Parse parses a strategy file and returns a Strategy object
func Parse(ctx context.Context, filePath string, gameFilterEnabled bool) (*Strategy, error) {
	select {
	case <-ctx.Done():
		return nil, errors.Wrap(ctx.Err(), "context canceled during strategy parsing")
	default:
	}

	slog.Debug("Parsing strategy file", "file", filePath, "gamefilter", gameFilterEnabled)

	file, err := os.Open(filePath)
	if err != nil {
		return nil, errors.NewStrategyError(filePath, 0, fmt.Sprintf("failed to open file: %v", err))
	}
	defer file.Close()

	strategy := &Strategy{
		FirewallRules: make([]FirewallRule, 0),
		NFQWSParams:   make([]NFQWSParams, 0),
		RawLines:      make([]string, 0),
	}

	scanner := bufio.NewScanner(file)
	lineNum := 0
	queueNum := 0

	for scanner.Scan() {
		lineNum++
		line := scanner.Text()

		// Skip comments and empty lines
		if isCommentOrEmpty(line) {
			continue
		}

		// Apply placeholders
		processedLine := applyPlaceholders(line, gameFilterEnabled)
		strategy.RawLines = append(strategy.RawLines, processedLine)

		// Parse firewall rules
		if rule, params, matched := parseFirewallRule(processedLine, queueNum); matched {
			strategy.FirewallRules = append(strategy.FirewallRules, rule)
			strategy.NFQWSParams = append(strategy.NFQWSParams, params)
			queueNum++
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, errors.NewStrategyError(filePath, lineNum, fmt.Sprintf("scanner error: %v", err))
	}

	slog.Debug("Strategy parsed successfully", "file", filePath, "firewall_rules", len(strategy.FirewallRules), "nfqws_params", len(strategy.NFQWSParams))

	return strategy, nil
}

func isCommentOrEmpty(line string) bool {
	trimmed := strings.TrimSpace(line)
	return trimmed == "" || strings.HasPrefix(trimmed, "::") || strings.HasPrefix(trimmed, "rem")
}

func applyPlaceholders(line string, gameFilterEnabled bool) string {
	// Replace %BIN% with "bin/"
	line = strings.ReplaceAll(line, BinPlaceholder, "bin/")

	// Replace %LISTS% with "lists/"
	line = strings.ReplaceAll(line, ListsPlaceholder, "lists/")

	// Handle GameFilter
	if gameFilterEnabled {
		// Replace %GameFilter% with ports
		line = strings.ReplaceAll(line, GameFilterPlaceholder, GameFilterPorts)
	} else {
		// Remove GameFilter from port lists
		line = strings.ReplaceAll(line, ","+GameFilterPlaceholder, "")
		line = strings.ReplaceAll(line, GameFilterPlaceholder+",", "")
	}

	return line
}

func parseFirewallRule(line string, queueNum int) (FirewallRule, NFQWSParams, bool) {
	// Regex pattern to match firewall rules
	// Example: --filter-tcp=1-65535 --new --filter-udp=1-65535 --new
	// We need to extract protocol, ports, and nfqws args
	pattern := `--filter-(tcp|udp)=([0-9,-]+)\s+(.+?)(?:--new|$)`
	regex := regexp.MustCompile(pattern)

	matches := regex.FindStringSubmatch(line)
	if len(matches) < 4 {
		return FirewallRule{}, NFQWSParams{}, false
	}

	protocol := matches[1]
	ports := matches[2]
	nfqwsArgs := matches[3]

	// Clean up nfqws args
	nfqwsArgs = strings.TrimSpace(nfqwsArgs)
	nfqwsArgs = strings.ReplaceAll(nfqwsArgs, "=^!", "=!")

	// Parse nfqws args into array
	args := parseNFQWSArgs(nfqwsArgs)

	return FirewallRule{
			Protocol: protocol,
			Ports:    ports,
			QueueNum: queueNum,
			Bypass:   false, // Default to no bypass
			RawRule:  fmt.Sprintf("%s dport {%s} counter queue num %d bypass", protocol, ports, queueNum),
		}, NFQWSParams{
			QueueNum: queueNum,
			Args:     args,
		}, true
}

func parseNFQWSArgs(argsString string) []string {
	var args []string

	// Simple parsing - split by space but handle quoted arguments
	var currentArg strings.Builder
	inQuotes := false

	for _, char := range argsString {
		switch char {
		case '"':
			inQuotes = !inQuotes
		case ' ':
			if inQuotes {
				currentArg.WriteRune(char)
			} else {
				if currentArg.Len() > 0 {
					args = append(args, currentArg.String())
					currentArg.Reset()
				}
			}
		default:
			currentArg.WriteRune(char)
		}
	}

	// Add the last argument
	if currentArg.Len() > 0 {
		args = append(args, currentArg.String())
	}

	return args
}

// Generic processing functions

// ProcessRules applies a generic function to each firewall rule
type RuleProcessor[T any] func(rule FirewallRule) (T, error)

func ProcessRules[T any](rules []FirewallRule, processor RuleProcessor[T]) ([]T, error) {
	results := make([]T, 0, len(rules))

	for _, rule := range rules {
		result, err := processor(rule)
		if err != nil {
			return nil, errors.Wrapf(err, "failed to process rule: %s", rule.RawRule)
		}
		results = append(results, result)
	}

	return results, nil
}

// ProcessNFQWSParams applies a generic function to each NFQWS parameter set
type NFQWSProcessor[T any] func(params NFQWSParams) (T, error)

func ProcessNFQWSParams[T any](params []NFQWSParams, processor NFQWSProcessor[T]) ([]T, error) {
	results := make([]T, 0, len(params))

	for _, param := range params {
		result, err := processor(param)
		if err != nil {
			return nil, errors.Wrapf(err, "failed to process NFQWS params for queue %d", param.QueueNum)
		}
		results = append(results, result)
	}

	return results, nil
}

// FindStrategyFiles finds available strategy files in the given directories
type StrategyFinder func(dir string) ([]string, error)

func FindStrategyFiles(dirs ...string) ([]string, error) {
	var files []string

	for _, dir := range dirs {
		entries, err := os.ReadDir(dir)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			return nil, errors.Wrapf(err, "failed to read directory %s", dir)
		}

		for _, entry := range entries {
			if strings.HasSuffix(entry.Name(), ".bat") {
				fullPath := filepath.Join(dir, entry.Name())
				files = append(files, fullPath)
			}
		}
	}

	return files, nil
}

// GetDefaultStrategyDirs returns the default directories where strategies are located
func GetDefaultStrategyDirs() []string {
	baseDir, err := os.Getwd()
	if err != nil {
		return []string{"zapret-latest", "custom-strategies"}
	}

	return []string{
		filepath.Join(baseDir, "zapret-latest"),
		filepath.Join(baseDir, "custom-strategies"),
	}
}
