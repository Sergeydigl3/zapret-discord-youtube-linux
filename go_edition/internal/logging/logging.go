// Package logging provides structured logging functionality for the Zapret application.
// It uses slog for structured logging with support for different output formats
// and log levels.
package logging

import (
	"log/slog"
	"os"
	"strings"
)

const (
	// DefaultLogLevel is the default logging level
	DefaultLogLevel = slog.LevelInfo
	// EnvLogLevel is the environment variable for log level
	EnvLogLevel = "ZAPRET_LOG_LEVEL"
	// EnvLogFormat is the environment variable for log format
	EnvLogFormat = "ZAPRET_LOG_FORMAT"
	// EnvLogColor is the environment variable for colored output
	EnvLogColor = "ZAPRET_LOG_COLOR"
)

// Initialize sets up the logging system
func Initialize(configValue *bool) {
	// Set log level from environment or use default
	logLevel := getLogLevel()

	// Configure output format
	output := getOutput()

	// Determine if we should use colorful logging
	useColor := shouldUseColor(configValue)

	// Create a new logger with the specified output and level
	var logger *slog.Logger
	if useColor {
		logger = slog.New(NewPrettyLoggingHandler(&slog.HandlerOptions{
			Level: logLevel,
		}))
	} else {
		logger = slog.New(slog.NewTextHandler(output, &slog.HandlerOptions{
			Level: logLevel,
		}))
	}

	// Set the global logger
	slog.SetDefault(logger)

	// Add context to logs
	slog.Info("Logging initialized", "app", "zapret", "color", useColor)
}

func getLogLevel() slog.Level {
	levelStr := strings.ToLower(os.Getenv(EnvLogLevel))

	switch levelStr {
	case "debug":
		return slog.LevelDebug
	case "info":
		return slog.LevelInfo
	case "warn", "warning":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	case "fatal":
		return slog.LevelError // slog doesn't have a Fatal level, use Error
	case "panic":
		return slog.LevelError // slog doesn't have a Panic level, use Error
	case "disabled", "none":
		return slog.Level(100) // High level to disable logging
	default:
		return DefaultLogLevel
	}
}

func getOutput() *os.File {
	format := strings.ToLower(os.Getenv(EnvLogFormat))

	switch format {
	case "json":
		return os.Stdout
	case "console", "text":
		return os.Stdout
	default:
		// Auto-detect: use JSON if running in container, console otherwise
		if isRunningInContainer() {
			return os.Stdout
		}
		return os.Stdout
	}
}

func shouldUseColor(configValue *bool) bool {
	// If config value is provided, use it
	if configValue != nil {
		return *configValue
	}

	// Fallback to environment variable
	colorStr := strings.ToLower(os.Getenv(EnvLogColor))

	switch colorStr {
	case "true", "1", "yes", "on":
		return true
	case "false", "0", "no", "off":
		return false
	default:
		// Auto-detect: use color if not running in container and stdout is a terminal
		if isRunningInContainer() {
			return false
		}
		// Check if stdout is a terminal
		fileInfo, _ := os.Stdout.Stat()
		if (fileInfo.Mode() & os.ModeCharDevice) != 0 {
			return true
		}
		return false
	}
}

func isRunningInContainer() bool {
	// Simple check for container environment
	if _, err := os.Stat("/.dockerenv"); err == nil {
		return true
	}

	// Check for common container-specific files
	if _, err := os.Stat("/proc/1/cgroup"); err == nil {
		// This is a heuristic, not definitive
		return true
	}

	return false
}
