// Package main provides the CLI utility for controlling the Zapret daemon
package main

import (
	"context"
	"fmt"
	"net/http"
	"os"

	"github.com/spf13/cobra"

	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/twirp"
	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/zapret-daemon"
)

var (
	// Version is set during build
	Version = "dev"
	// BuildDate is set during build
	BuildDate = "unknown"
	
	// Global Twirp client
	twirpClient twirp.ZapretServiceClient
)

func main() {
	// Initialize Twirp client
	socketPath := twirp.GetSocketPath()
	baseURL := fmt.Sprintf("http://%s", socketPath)
	twirpClient = twirp.NewZapretServiceProtobufClient(baseURL, &http.Client{})

	// Create root command
	rootCmd := &cobra.Command{
		Use:     "zapret-cli",
		Short:   "Zapret CLI - Control Zapret daemon",
		Long:    "Command line interface for controlling the Zapret daemon.",
		Version: fmt.Sprintf("%s (%s)", Version, BuildDate),
	}

	// Add subcommands
	rootCmd.AddCommand(createStatusCommand())
	rootCmd.AddCommand(createStartCommand())
	rootCmd.AddCommand(createStopCommand())
	rootCmd.AddCommand(createRestartCommand())
	rootCmd.AddCommand(createConfigCommand())
	rootCmd.AddCommand(createFirewallCommand())
	rootCmd.AddCommand(createProcessesCommand())

	// Execute the command
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func createStatusCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "status",
		Short: "Check daemon status",
		Long:  "Get the current status of the Zapret daemon.",
		RunE: func(cmd *cobra.Command, args []string) error {
			// Get active processes to check if daemon is running
			resp, err := twirpClient.GetActiveProcesses(context.Background(), &zapretdaemon.GetActiveProcessesRequest{})
			if err != nil {
				return fmt.Errorf("failed to get daemon status: %w", err)
			}
			
			fmt.Printf("Daemon Status: Running\n")
			fmt.Printf("Active Processes: %d\n", len(resp.Processes))
			for i, process := range resp.Processes {
				fmt.Printf("  %d. %s\n", i+1, process)
			}
			return nil
		},
	}
}

func createStartCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "start",
		Short: "Start the application",
		Long:  "Start the Zapret application if it's not already running.",
		RunE: func(cmd *cobra.Command, args []string) error {
			// Start a default strategy
			resp, err := twirpClient.RunSelectedStrategy(context.Background(), &zapretdaemon.RunSelectedStrategyRequest{
				StrategyPath: "default.bat",
			})
			if err != nil {
				return fmt.Errorf("failed to start application: %w", err)
			}
			
			fmt.Printf("Application started successfully: %s\n", resp.Message)
			return nil
		},
	}
}

func createStopCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "stop",
		Short: "Stop the application",
		Long:  "Stop the Zapret application if it's running.",
		RunE: func(cmd *cobra.Command, args []string) error {
			resp, err := twirpClient.StopStrategy(context.Background(), &zapretdaemon.StopStrategyRequest{})
			if err != nil {
				return fmt.Errorf("failed to stop application: %w", err)
			}
			
			fmt.Printf("Application stopped successfully: %s\n", resp.Message)
			return nil
		},
	}
}

func createRestartCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "restart",
		Short: "Restart the application",
		Long:  "Restart the Zapret application.",
		RunE: func(cmd *cobra.Command, args []string) error {
			resp, err := twirpClient.RestartDaemon(context.Background(), &zapretdaemon.RestartDaemonRequest{})
			if err != nil {
				return fmt.Errorf("failed to restart daemon: %w", err)
			}
			
			fmt.Printf("Daemon restarted successfully: %s\n", resp.Message)
			return nil
		},
	}
}

func createConfigCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "config",
		Short: "Get current configuration",
		Long:  "Display the current configuration of the Zapret daemon.",
		RunE: func(cmd *cobra.Command, args []string) error {
			// Get available versions as part of configuration
			resp, err := twirpClient.GetAvailableVersions(context.Background(), &zapretdaemon.GetAvailableVersionsRequest{})
			if err != nil {
				return fmt.Errorf("failed to get configuration: %w", err)
			}
			
			fmt.Printf("Available Versions:\n")
			for i, version := range resp.Versions {
				fmt.Printf("  %d. %s\n", i+1, version)
			}
			
			// Get active NFT rules
			rulesResp, err := twirpClient.GetActiveNFTRules(context.Background(), &zapretdaemon.GetActiveNFTRulesRequest{})
			if err != nil {
				return fmt.Errorf("failed to get NFT rules: %w", err)
			}
			
			fmt.Printf("\nActive NFT Rules:\n")
			for i, rule := range rulesResp.Rules {
				fmt.Printf("  %d. %s\n", i+1, rule)
			}
			
			return nil
		},
	}
}

func createFirewallCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "firewall",
		Short: "Get firewall status",
		Long:  "Display the current firewall status and rules.",
		RunE: func(cmd *cobra.Command, args []string) error {
			// Get active NFT rules (firewall rules)
			resp, err := twirpClient.GetActiveNFTRules(context.Background(), &zapretdaemon.GetActiveNFTRulesRequest{})
			if err != nil {
				return fmt.Errorf("failed to get firewall status: %w", err)
			}
			
			fmt.Printf("Firewall Status: Active\n")
			fmt.Printf("Active NFT Rules: %d\n", len(resp.Rules))
			for i, rule := range resp.Rules {
				fmt.Printf("  %d. %s\n", i+1, rule)
			}
			return nil
		},
	}
}

func createProcessesCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "processes",
		Short: "Get process status",
		Long:  "Display the status of NFQWS processes and active queues.",
		RunE: func(cmd *cobra.Command, args []string) error {
			resp, err := twirpClient.GetActiveProcesses(context.Background(), &zapretdaemon.GetActiveProcessesRequest{})
			if err != nil {
				return fmt.Errorf("failed to get process status: %w", err)
			}
			
			fmt.Printf("Active Processes: %d\n", len(resp.Processes))
			for i, process := range resp.Processes {
				fmt.Printf("  %d. %s\n", i+1, process)
			}
			return nil
		},
	}
}

// getSocketPath returns the socket path from environment or uses default
func getSocketPath() string {
	if socketPath := os.Getenv("ZAPRET_SOCKET_PATH"); socketPath != "" {
		return socketPath
	}
	return twirp.GetDefaultSocketPath()
}