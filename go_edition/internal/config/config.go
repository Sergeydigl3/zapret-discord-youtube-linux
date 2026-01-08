// Package config provides configuration management for the Zapret application.
// It supports loading configuration from environment variables and config files,
// with validation and type-safe access to configuration values.
package config

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/viper"
)

const (
	// DefaultConfigFile is the default configuration file name
	DefaultConfigFile = "conf.yml"
	// EnvPrefix is the prefix for environment variables
	EnvPrefix = "ZAPRET"
)

// Config represents the application configuration
type Config struct {
	// StrategyPath is the path to the strategy file
	StrategyPath string `mapstructure:"strategy" validate:"required"`
	// Interface is the network interface to filter
	Interface string `mapstructure:"interface" validate:"required"`
	// GameFilterEnabled indicates whether game filter is enabled
	GameFilterEnabled bool `mapstructure:"gamefilter"`
	// NFQWSBinaryPath is the path to the nfqws binary
	NFQWSBinaryPath string `mapstructure:"nfqws_path"`
	// DebugMode enables debug logging
	DebugMode bool `mapstructure:"debug"`
	// NoInteractive disables interactive mode
	NoInteractive bool `mapstructure:"nointeractive"`
	// LogColor enables colored logging output
	LogColor *bool `mapstructure:"log_color"`
	
	// Daemon-specific configuration
	SocketPath string `mapstructure:"socket_path"`
	PidFile    string `mapstructure:"pid_file"`
	LogFile    string `mapstructure:"log_file"`
}

// Manager handles configuration operations
type Manager struct {
	viper *viper.Viper
}

// NewManager creates a new configuration manager
func NewManager() *Manager {
	return &Manager{
		viper: viper.New(),
	}
}

// Load loads configuration from file and environment variables
func Load(ctx context.Context) (*Config, error) {
	manager := NewManager()
	return manager.Load(ctx)
}

// Load loads configuration from file and environment variables
func (m *Manager) Load(ctx context.Context) (*Config, error) {
	select {
	case <-ctx.Done():
		return nil, fmt.Errorf("context canceled: %w", ctx.Err())
	default:
	}

	// Set up viper
	m.viper.SetEnvPrefix(EnvPrefix)
	m.viper.AutomaticEnv()
	m.viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))

	// Set defaults
	m.setDefaults()

	// Try to load from config file
	if err := m.loadFromFile(); err != nil {
		// If file doesn't exist and we're not in no-interactive mode, that's ok
		if !errors.Is(err, os.ErrNotExist) {
			return nil, fmt.Errorf("failed to load config file: %w", err)
		}
	}

	// Validate required configuration
	if err := m.validate(); err != nil {
		return nil, fmt.Errorf("configuration validation failed: %w", err)
	}

	// Unmarshal into Config struct
	var cfg Config
	if err := m.viper.Unmarshal(&cfg); err != nil {
		return nil, fmt.Errorf("failed to unmarshal config: %w", err)
	}

	// Set default paths if not specified
	if cfg.NFQWSBinaryPath == "" {
		cfg.NFQWSBinaryPath = filepath.Join(getBaseDir(), "nfqws")
	}

	// Set default value for LogColor if not specified
	if cfg.LogColor == nil {
		defaultColor := true
		cfg.LogColor = &defaultColor
	}

	// Resolve strategy path
	if !filepath.IsAbs(cfg.StrategyPath) {
		cfg.StrategyPath = filepath.Join(getBaseDir(), "zapret-latest", cfg.StrategyPath)
	}

	slog.Debug("Configuration loaded", "strategy", cfg.StrategyPath, "interface", cfg.Interface, "gamefilter", cfg.GameFilterEnabled, "nfqws_path", cfg.NFQWSBinaryPath)

	return &cfg, nil
}

func (m *Manager) setDefaults() {
	// Set reasonable defaults
	m.viper.SetDefault("debug", false)
	m.viper.SetDefault("nointeractive", false)
	m.viper.SetDefault("gamefilter", false)
	m.viper.SetDefault("log_color", true)
	
	// Daemon defaults
	m.viper.SetDefault("socket_path", "/var/run/zapret.sock")
	m.viper.SetDefault("pid_file", "/var/run/zapret.pid")
	m.viper.SetDefault("log_file", "/var/log/zapret/daemon.log")
}

func (m *Manager) loadFromFile() error {
	// Try to find config file in current directory or parent directories
	configPath, err := findConfigFile()
	if err != nil {
		return fmt.Errorf("failed to find config file: %w", err)
	}

	if configPath == "" {
		return os.ErrNotExist
	}

	m.viper.SetConfigFile(configPath)
	m.viper.SetConfigType("yaml")

	if err := m.viper.ReadInConfig(); err != nil {
		return fmt.Errorf("failed to read config file: %w", err)
	}

	slog.Debug("Loaded configuration from file", "config_file", configPath)
	return nil
}

func findConfigFile() (string, error) {
	// Check current directory first
	if _, err := os.Stat(DefaultConfigFile); err == nil {
		return DefaultConfigFile, nil
	}

	// Check parent directories up to 3 levels
	currentDir, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("failed to get current directory: %w", err)
	}

	for i := 0; i < 3; i++ {
		configPath := filepath.Join(currentDir, DefaultConfigFile)
		if _, err := os.Stat(configPath); err == nil {
			return configPath, nil
		}

		parentDir := filepath.Dir(currentDir)
		if parentDir == currentDir {
			break // Reached root
		}
		currentDir = parentDir
	}

	return "", nil
}

func (m *Manager) validate() error {
	// Check required fields
	if !m.viper.IsSet("strategy") || m.viper.GetString("strategy") == "" {
		return errors.New("strategy is required")
	}

	if !m.viper.IsSet("interface") || m.viper.GetString("interface") == "" {
		return errors.New("interface is required")
	}

	// Validate strategy file exists
	strategyPath := m.viper.GetString("strategy")
	if !filepath.IsAbs(strategyPath) {
		strategyPath = filepath.Join(getBaseDir(), "zapret-latest", strategyPath)
	}

	if _, err := os.Stat(strategyPath); err != nil {
		return fmt.Errorf("strategy file not found: %w", err)
	}

	// Validate interface exists (basic check)
	interfaceName := m.viper.GetString("interface")
	if interfaceName != "any" {
		if _, err := os.Stat(filepath.Join("/sys/class/net", interfaceName)); err != nil {
			slog.Warn("Network interface not found", "interface", interfaceName)
		}
	}

	return nil
}

func getBaseDir() string {
	exePath, err := os.Executable()
	if err != nil {
		return "."
	}
	return filepath.Dir(exePath)
}

// CreateInteractive creates configuration interactively
func (m *Manager) CreateInteractive() error {
	slog.Info("Creating new configuration interactively...")

	// Find available strategies
	strategies, err := findAvailableStrategies()
	if err != nil {
		return fmt.Errorf("failed to find strategies: %w", err)
	}

	// Find available network interfaces
	interfaces, err := findNetworkInterfaces()
	if err != nil {
		return fmt.Errorf("failed to find network interfaces: %w", err)
	}

	// Ask user for configuration
	strategy := askChoice("Select strategy", strategies)
	iface := askChoice("Select network interface", interfaces)
	gameFilter := askBool("Enable GameFilter?", false)

	// Create config in YAML format
	configContent := fmt.Sprintf(`# Zapret Discord YouTube Go Edition - Configuration File
# This file contains the main configuration for the application

# Strategy file to use (relative to zapret-latest directory or absolute path)
strategy: %s

# Network interface to filter (use "any" for all interfaces)
interface: %s

# Enable GameFilter to exclude game ports from filtering
gamefilter: %t

# Path to nfqws binary (default: ./nfqws)
# nfqws_path: ./nfqws

# Enable debug logging
debug: false

# Run in non-interactive mode
nointeractive: false
`,
		strategy, iface, gameFilter)

	// Write to config file
	if err := os.WriteFile(DefaultConfigFile, []byte(configContent), 0644); err != nil {
		return fmt.Errorf("failed to write config file: %w", err)
	}

	slog.Info("Configuration created successfully", "file", DefaultConfigFile)
	return nil
}

func findAvailableStrategies() ([]string, error) {
	baseDir := getBaseDir()
	strategyDirs := []string{
		filepath.Join(baseDir, "zapret-latest"),
		filepath.Join(baseDir, "custom-strategies"),
	}

	var strategies []string
	for _, dir := range strategyDirs {
		files, err := os.ReadDir(dir)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			return nil, fmt.Errorf("failed to read directory %s: %w", dir, err)
		}

		for _, file := range files {
			if strings.HasSuffix(file.Name(), ".bat") {
				strategies = append(strategies, file.Name())
			}
		}
	}

	if len(strategies) == 0 {
		return nil, errors.New("no strategy files found")
	}

	return strategies, nil
}

func findNetworkInterfaces() ([]string, error) {
	files, err := os.ReadDir("/sys/class/net")
	if err != nil {
		return nil, fmt.Errorf("failed to read network interfaces: %w", err)
	}

	var interfaces []string
	interfaces = append(interfaces, "any")

	for _, file := range files {
		interfaces = append(interfaces, file.Name())
	}

	return interfaces, nil
}

func askChoice(prompt string, options []string) string {
	fmt.Printf("%s:\n", prompt)
	for i, option := range options {
		fmt.Printf("  %d) %s\n", i+1, option)
	}

	var choice int
	fmt.Print("Enter choice: ")
	_, err := fmt.Scanf("%d", &choice)
	if err != nil || choice < 1 || choice > len(options) {
		slog.Error("Invalid choice", "error", err)
		os.Exit(1)
	}

	return options[choice-1]
}

func askBool(prompt string, defaultValue bool) bool {
	fmt.Printf("%s [y/N]: ", prompt)
	var response string
	fmt.Scanln(&response)
	return strings.ToLower(response) == "y" || strings.ToLower(response) == "yes"
}

// Validate checks if the current configuration is valid
func (m *Manager) Validate() error {
	_, err := m.Load(context.Background())
	if err != nil {
		return fmt.Errorf("configuration validation failed: %w", err)
	}
	slog.Info("Configuration is valid")
	return nil
}

// Show displays the current configuration
func (m *Manager) Show() error {
	cfg, err := m.Load(context.Background())
	if err != nil {
		return fmt.Errorf("failed to load configuration: %w", err)
	}

	slog.Info("Current Configuration:")
	slog.Info("  Strategy", "strategy", cfg.StrategyPath)
	slog.Info("  Interface", "interface", cfg.Interface)
	slog.Info("  GameFilter", "gamefilter", cfg.GameFilterEnabled)
	slog.Info("  NFQWS Path", "nfqws_path", cfg.NFQWSBinaryPath)
	slog.Info("  Debug Mode", "debug", cfg.DebugMode)
	logColorValue := false
	if cfg.LogColor != nil {
		logColorValue = *cfg.LogColor
	}
	slog.Info("  Log Color", "log_color", logColorValue)

	return nil
}
