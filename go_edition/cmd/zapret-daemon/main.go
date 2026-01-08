// Package main provides the entry point for the Zapret daemon
package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/config"
	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/firewall"
	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/ipc"
	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/logging"
	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/nfqws"
	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/strategy"
	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/zapret-daemon"
)

var (
	// Version is set during build
	Version = "dev"
	// BuildDate is set during build
	BuildDate = "unknown"
)

// Application represents the main application
type Application struct {
	ctx            context.Context
	config         *config.Config
	ipcServer      *ipc.UnixSocketServer
	firewallManager *firewall.Manager
	nfqwsManager   *nfqws.Manager
	strategy       *strategy.Strategy
	isRunning      bool
	twirpServer    *twirp.MinimalServer
}

func main() {
	// Parse command line flags
	_ = flag.String("config", "/etc/zapret/conf.yml", "Path to config file")
	socketPath := flag.String("socket", "", "Unix socket path (overrides config)")
	flag.Parse()

	// Initialize logging
	logging.Initialize(nil)
	slog.Info("Starting Zapret Daemon", "version", Version, "build_date", BuildDate)

	// Load configuration
	cfg, err := config.Load(context.Background())
	if err != nil {
		slog.Error("Failed to load configuration", "error", err)
		os.Exit(1)
	}

	// Use socket path from command line or config
	finalSocketPath := cfg.SocketPath
	if *socketPath != "" {
		finalSocketPath = *socketPath
	}

	// Ensure socket directory exists
	if err := ipc.EnsureSocketDirectory(finalSocketPath); err != nil {
		slog.Error("Failed to ensure socket directory", "error", err)
		os.Exit(1)
	}

	// Create context for graceful shutdown
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Create IPC server
	ipcServer := ipc.NewUnixSocketServer(finalSocketPath, ipc.WithContext(ctx))

	// Create application
	app := &Application{
		ctx:        ctx,
		config:     cfg,
		ipcServer:  ipcServer,
		isRunning:  false,
	}

	// Initialize Twirp service
	twirpService := twirp.NewZapretServiceImpl()
	app.twirpServer = twirp.NewMinimalServer(twirpService, twirp.WithMinimalPort(8080))

	// Register IPC commands
	app.registerCommands()

	// Start IPC server
	if err := ipcServer.Start(); err != nil {
		slog.Error("Failed to start IPC server", "error", err)
		os.Exit(1)
	}
	defer ipcServer.Stop()

	// Start Twirp server
	if err := app.twirpServer.Start(); err != nil {
		slog.Error("Failed to start Twirp server", "error", err)
		os.Exit(1)
	}
	defer app.twirpServer.Stop()

	// Handle signals for graceful shutdown
	go app.handleSignals(cancel)

	// Start the application
	if err := app.Start(); err != nil {
		slog.Error("Application failed", "error", err)
		os.Exit(1)
	}

	// Wait for shutdown
	<-ctx.Done()
	slog.Info("Shutting down gracefully...")

	// Cleanup
	if cleanupErr := app.Stop(); cleanupErr != nil {
		slog.Error("Failed to cleanup application", "error", cleanupErr)
	}
}

// Start starts the application
func (app *Application) Start() error {
	if app.isRunning {
		return fmt.Errorf("application is already running")
	}

	slog.Info("Starting application...")

	// Parse strategy
	strat, err := strategy.Parse(app.ctx, app.config.StrategyPath, app.config.GameFilterEnabled)
	if err != nil {
		return fmt.Errorf("failed to parse strategy: %w", err)
	}
	app.strategy = strat

	// Initialize firewall manager
	fwManager, err := firewall.NewManager(app.ctx, app.config.Interface)
	if err != nil {
		return fmt.Errorf("failed to initialize firewall manager: %w", err)
	}
	app.firewallManager = fwManager

	// Setup firewall rules
	if err := fwManager.SetupRules(app.ctx, strat.FirewallRules); err != nil {
		return fmt.Errorf("failed to setup firewall rules: %w", err)
	}

	// Initialize NFQWS process manager
	nfqwsManager := nfqws.NewManager(app.config.NFQWSBinaryPath)
	app.nfqwsManager = nfqwsManager

	// Start NFQWS processes
	if err := nfqwsManager.StartProcesses(app.ctx, strat.NFQWSParams); err != nil {
		return fmt.Errorf("failed to start NFQWS processes: %w", err)
	}

	app.isRunning = true
	slog.Info("Application started successfully")

	return nil
}

// Stop stops the application
func (app *Application) Stop() error {
	if !app.isRunning {
		return nil
	}

	slog.Info("Stopping application...")

	// Cleanup NFQWS processes
	if app.nfqwsManager != nil {
		if err := app.nfqwsManager.Cleanup(app.ctx); err != nil {
			slog.Error("Failed to cleanup NFQWS processes", "error", err)
		}
	}

	// Cleanup firewall rules
	if app.firewallManager != nil {
		if err := app.firewallManager.Cleanup(app.ctx); err != nil {
			slog.Error("Failed to cleanup firewall", "error", err)
		}
	}

	app.isRunning = false
	slog.Info("Application stopped successfully")

	return nil
}

// handleSignals handles OS signals for graceful shutdown
func (app *Application) handleSignals(cancel context.CancelFunc) {
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	<-sigChan
	slog.Info("Received shutdown signal")
	cancel()
}

// registerCommands registers all IPC commands
func (app *Application) registerCommands() {
	app.ipcServer.RegisterCommand(ipc.CommandRegistration{
		Name:        "status",
		Handler:     app.handleStatusCommand,
		Description: "Get daemon status",
	})

	app.ipcServer.RegisterCommand(ipc.CommandRegistration{
		Name:        "start",
		Handler:     app.handleStartCommand,
		Description: "Start the application",
	})

	app.ipcServer.RegisterCommand(ipc.CommandRegistration{
		Name:        "stop",
		Handler:     app.handleStopCommand,
		Description: "Stop the application",
	})

	app.ipcServer.RegisterCommand(ipc.CommandRegistration{
		Name:        "restart",
		Handler:     app.handleRestartCommand,
		Description: "Restart the application",
	})

	app.ipcServer.RegisterCommand(ipc.CommandRegistration{
		Name:        "config",
		Handler:     app.handleConfigCommand,
		Description: "Get current configuration",
	})

	app.ipcServer.RegisterCommand(ipc.CommandRegistration{
		Name:        "firewall",
		Handler:     app.handleFirewallCommand,
		Description: "Get firewall status",
	})

	app.ipcServer.RegisterCommand(ipc.CommandRegistration{
		Name:        "processes",
		Handler:     app.handleProcessesCommand,
		Description: "Get process status",
	})
}

// handleStatusCommand handles the status command
func (app *Application) handleStatusCommand(ctx context.Context, params map[string]interface{}) (interface{}, error) {
	var startTime time.Time
	if app.isRunning {
		// In a real implementation, we would track the actual start time
		startTime = time.Now().Add(-time.Since(time.Now()))
	}

	firewallRules := 0
	if app.firewallManager != nil {
		status, err := app.firewallManager.Status(ctx)
		if err == nil {
			firewallRules = status.RuleCount
		}
	}

	nfqwsProcesses := 0
	if app.nfqwsManager != nil {
		status, err := app.nfqwsManager.Status(ctx)
		if err == nil {
			nfqwsProcesses = status.ProcessCount
		}
	}

	return ipc.StatusResponse{
		Status:          getStatusString(app.isRunning),
		Uptime:          getUptimeString(startTime),
		FirewallRules:   firewallRules,
		NFQWSProcesses:  nfqwsProcesses,
		StrategyPath:    app.config.StrategyPath,
		StartTime:       startTime,
		Running:         app.isRunning,
	}, nil
}

// handleStartCommand handles the start command
func (app *Application) handleStartCommand(ctx context.Context, params map[string]interface{}) (interface{}, error) {
	if app.isRunning {
		return nil, fmt.Errorf("application is already running")
	}

	if err := app.Start(); err != nil {
		return nil, fmt.Errorf("failed to start application: %w", err)
	}

	return map[string]string{"status": "started"}, nil
}

// handleStopCommand handles the stop command
func (app *Application) handleStopCommand(ctx context.Context, params map[string]interface{}) (interface{}, error) {
	if !app.isRunning {
		return nil, fmt.Errorf("application is not running")
	}

	if err := app.Stop(); err != nil {
		return nil, fmt.Errorf("failed to stop application: %w", err)
	}

	return map[string]string{"status": "stopped"}, nil
}

// handleRestartCommand handles the restart command
func (app *Application) handleRestartCommand(ctx context.Context, params map[string]interface{}) (interface{}, error) {
	if err := app.Stop(); err != nil {
		return nil, fmt.Errorf("failed to stop application: %w", err)
	}

	if err := app.Start(); err != nil {
		return nil, fmt.Errorf("failed to start application: %w", err)
	}

	return map[string]string{"status": "restarted"}, nil
}

// handleConfigCommand handles the config command
func (app *Application) handleConfigCommand(ctx context.Context, params map[string]interface{}) (interface{}, error) {
	return app.config, nil
}

// handleFirewallCommand handles the firewall command
func (app *Application) handleFirewallCommand(ctx context.Context, params map[string]interface{}) (interface{}, error) {
	if app.firewallManager == nil {
		return nil, fmt.Errorf("firewall manager not initialized")
	}

	status, err := app.firewallManager.Status(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get firewall status: %w", err)
	}

	return status, nil
}

// handleProcessesCommand handles the processes command
func (app *Application) handleProcessesCommand(ctx context.Context, params map[string]interface{}) (interface{}, error) {
	if app.nfqwsManager == nil {
		return nil, fmt.Errorf("NFQWS manager not initialized")
	}

	status, err := app.nfqwsManager.Status(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get process status: %w", err)
	}

	return status, nil
}

// Helper functions
func getStatusString(running bool) string {
	if running {
		return "running"
	}
	return "stopped"
}

func getUptimeString(startTime time.Time) string {
	if startTime.IsZero() {
		return "0s"
	}
	return time.Since(startTime).String()
}