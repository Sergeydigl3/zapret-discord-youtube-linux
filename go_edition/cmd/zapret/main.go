// Package main provides the entry point for the Zapret Discord YouTube Go application.
// This application manages network filtering to bypass YouTube throttling using
// NFQUEUE and nfqws processes with configurable strategies.
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/spf13/cobra"

	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/config"
	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/firewall"
	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/logging"
	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/nfqws"
	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/service"
	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/strategy"
)

var (
	// Version is set during build
	Version = "dev"
	// BuildDate is set during build
	BuildDate = "unknown"
)

func main() {
	// Initialize basic logging (without color for early logging)
	logging.Initialize(nil)
	slog.Info("Starting Zapret Discord YouTube Go Edition", "version", Version, "build_date", BuildDate)

	// Create root command
	rootCmd := &cobra.Command{
		Use:     "zapret",
		Short:   "Zapret Discord YouTube - Network filtering system to bypass YouTube throttling",
		Long:    "A high-performance Go implementation of the Zapret Discord YouTube network filtering system.",
		Version: fmt.Sprintf("%s (%s)", Version, BuildDate),
		RunE:    runMain,
	}

	// Add subcommands
	rootCmd.AddCommand(createServiceCommand())
	rootCmd.AddCommand(createConfigCommand())
	rootCmd.AddCommand(createDebugCommand())

	// Execute the command
	if err := rootCmd.Execute(); err != nil {
		slog.Error("Application failed", "error", err)
		os.Exit(1)
	}
}

func runMain(cmd *cobra.Command, args []string) error {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Handle graceful shutdown
	go handleSignals(cancel)

	// Load configuration
	cfg, err := config.Load(ctx)
	if err != nil {
		return fmt.Errorf("failed to load configuration: %w", err)
	}

	// Re-initialize logging with proper color setting from configuration
	logging.Initialize(cfg.LogColor)
	colorValue := true
	if cfg.LogColor != nil {
		colorValue = *cfg.LogColor
	}
	slog.Info("Logging re-initialized with configuration", "color", colorValue)

	// Parse strategy
	strat, err := strategy.Parse(ctx, cfg.StrategyPath, cfg.GameFilterEnabled)
	if err != nil {
		return fmt.Errorf("failed to parse strategy: %w", err)
	}

	// Initialize firewall manager
	fwManager, err := firewall.NewManager(ctx, cfg.Interface)
	if err != nil {
		return fmt.Errorf("failed to initialize firewall manager: %w", err)
	}
	defer func() {
		if cleanupErr := fwManager.Cleanup(ctx); cleanupErr != nil {
			slog.Error("Failed to cleanup firewall", "error", cleanupErr)
		}
	}()

	// Setup firewall rules
	if err := fwManager.SetupRules(ctx, strat.FirewallRules); err != nil {
		return fmt.Errorf("failed to setup firewall rules: %w", err)
	}

	// Initialize NFQWS process manager
	nfqwsManager := nfqws.NewManager(cfg.NFQWSBinaryPath)
	defer func() {
		if cleanupErr := nfqwsManager.Cleanup(ctx); cleanupErr != nil {
			slog.Error("Failed to cleanup NFQWS processes", "error", cleanupErr)
		}
	}()

	// Start NFQWS processes
	if err := nfqwsManager.StartProcesses(ctx, strat.NFQWSParams); err != nil {
		return fmt.Errorf("failed to start NFQWS processes: %w", err)
	}

	slog.Info("Zapret Discord YouTube is running. Press Ctrl+C to exit.")

	// Wait for shutdown signal
	<-ctx.Done()
	slog.Info("Shutting down gracefully...")

	return nil
}

func handleSignals(cancel context.CancelFunc) {
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	<-sigChan
	slog.Info("Received shutdown signal")
	cancel()
}

func createServiceCommand() *cobra.Command {
	serviceCmd := &cobra.Command{
		Use:   "service",
		Short: "Manage system service installation",
		Long:  "Install, remove, start, stop, or check the status of the Zapret service.",
	}

	var installCmd = &cobra.Command{
		Use:   "install",
		Short: "Install Zapret service",
		Long:  "Install the Zapret service on the system.",
		RunE: func(cmd *cobra.Command, args []string) error {
			serviceManager, err := service.NewManager()
			if err != nil {
				return fmt.Errorf("failed to create service manager: %w", err)
			}
			return serviceManager.Install()
		},
	}

	var removeCmd = &cobra.Command{
		Use:   "remove",
		Short: "Remove Zapret service",
		Long:  "Remove the Zapret service from the system.",
		RunE: func(cmd *cobra.Command, args []string) error {
			serviceManager, err := service.NewManager()
			if err != nil {
				return fmt.Errorf("failed to create service manager: %w", err)
			}
			return serviceManager.Remove()
		},
	}

	var startCmd = &cobra.Command{
		Use:   "start",
		Short: "Start Zapret service",
		Long:  "Start the Zapret service.",
		RunE: func(cmd *cobra.Command, args []string) error {
			serviceManager, err := service.NewManager()
			if err != nil {
				return fmt.Errorf("failed to create service manager: %w", err)
			}
			return serviceManager.Start()
		},
	}

	var stopCmd = &cobra.Command{
		Use:   "stop",
		Short: "Stop Zapret service",
		Long:  "Stop the Zapret service.",
		RunE: func(cmd *cobra.Command, args []string) error {
			serviceManager, err := service.NewManager()
			if err != nil {
				return fmt.Errorf("failed to create service manager: %w", err)
			}
			return serviceManager.Stop()
		},
	}

	var statusCmd = &cobra.Command{
		Use:   "status",
		Short: "Check Zapret service status",
		Long:  "Check the status of the Zapret service.",
		RunE: func(cmd *cobra.Command, args []string) error {
			serviceManager, err := service.NewManager()
			if err != nil {
				return fmt.Errorf("failed to create service manager: %w", err)
			}
			return serviceManager.Status()
		},
	}

	serviceCmd.AddCommand(installCmd)
	serviceCmd.AddCommand(removeCmd)
	serviceCmd.AddCommand(startCmd)
	serviceCmd.AddCommand(stopCmd)
	serviceCmd.AddCommand(statusCmd)

	return serviceCmd
}

func createConfigCommand() *cobra.Command {
	configCmd := &cobra.Command{
		Use:   "config",
		Short: "Manage configuration",
		Long:  "Create, validate, or show the current configuration.",
	}

	var createCmd = &cobra.Command{
		Use:   "create",
		Short: "Create configuration",
		Long:  "Create a new configuration interactively.",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfgManager := config.NewManager()
			return cfgManager.CreateInteractive()
		},
	}

	var validateCmd = &cobra.Command{
		Use:   "validate",
		Short: "Validate configuration",
		Long:  "Validate the current configuration.",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfgManager := config.NewManager()
			return cfgManager.Validate()
		},
	}

	var showCmd = &cobra.Command{
		Use:   "show",
		Short: "Show configuration",
		Long:  "Show the current configuration.",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfgManager := config.NewManager()
			return cfgManager.Show()
		},
	}

	configCmd.AddCommand(createCmd)
	configCmd.AddCommand(validateCmd)
	configCmd.AddCommand(showCmd)

	return configCmd
}

func createDebugCommand() *cobra.Command {
	debugCmd := &cobra.Command{
		Use:   "debug",
		Short: "Debug and diagnostic commands",
		Long:  "Run diagnostic commands and show system information.",
	}

	var infoCmd = &cobra.Command{
		Use:   "info",
		Short: "Show system information",
		Long:  "Display system information including Go version and OS/Arch.",
		RunE: func(cmd *cobra.Command, args []string) error {
			return showSystemInfo()
		},
	}

	var firewallCmd = &cobra.Command{
		Use:   "firewall",
		Short: "Show firewall status",
		Long:  "Display the current firewall status and rules.",
		RunE: func(cmd *cobra.Command, args []string) error {
			return showFirewallStatus()
		},
	}

	var processesCmd = &cobra.Command{
		Use:   "processes",
		Short: "Show process status",
		Long:  "Display the status of NFQWS processes and active queues.",
		RunE: func(cmd *cobra.Command, args []string) error {
			return showProcessStatus()
		},
	}

	debugCmd.AddCommand(infoCmd)
	debugCmd.AddCommand(firewallCmd)
	debugCmd.AddCommand(processesCmd)

	return debugCmd
}

func showSystemInfo() error {
	slog.Info("System Information:")
	slog.Info("  Go Version: 1.21+")
	slog.Info("  OS/Arch: linux/amd64")
	return nil
}

func showFirewallStatus() error {
	ctx := context.Background()
	fwManager, err := firewall.NewManager(ctx, "")
	if err != nil {
		return fmt.Errorf("failed to create firewall manager: %w", err)
	}

	status, err := fwManager.Status(ctx)
	if err != nil {
		return fmt.Errorf("failed to get firewall status: %w", err)
	}

	slog.Info("Firewall Status:")
	slog.Info("  Type", "type", status.Type)
	slog.Info("  Status", "status", status.Status)
	slog.Info("  Rules", "rules", status.RuleCount)

	return nil
}

func showProcessStatus() error {
	ctx := context.Background()
	cfg, err := config.Load(ctx)
	if err != nil {
		return fmt.Errorf("failed to load configuration: %w", err)
	}

	nfqwsManager := nfqws.NewManager(cfg.NFQWSBinaryPath)
	status, err := nfqwsManager.Status(ctx)
	if err != nil {
		return fmt.Errorf("failed to get process status: %w", err)
	}

	slog.Info("Process Status:")
	slog.Info("  NFQWS Processes", "processes", status.ProcessCount)
	slog.Info("  Active Queues", "queues", status.ActiveQueues)

	return nil
}
