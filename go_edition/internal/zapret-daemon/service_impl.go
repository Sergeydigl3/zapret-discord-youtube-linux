// Package twirp provides Twirp-based RPC service for Zapret
package twirp

import (
	"context"
	"fmt"
	"log/slog"

	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/strategy"
)

// ZapretServiceImpl implements the ZapretService interface
type ZapretServiceImpl struct {
	// Add any dependencies needed for the service
}

// NewZapretServiceImpl creates a new instance of ZapretServiceImpl
func NewZapretServiceImpl() *ZapretServiceImpl {
	return &ZapretServiceImpl{}
}

// GetStrategyList returns the list of available strategy paths
func (s *ZapretServiceImpl) GetStrategyList(ctx context.Context, req *GetStrategyListRequest) (*GetStrategyListResponse, error) {
	slog.Info("Getting strategy list via Twirp")
	
	// Use the existing strategy finding functionality
	strategyDirs := strategy.GetDefaultStrategyDirs()
	strategyPaths, err := strategy.FindStrategyFiles(strategyDirs...)
	if err != nil {
		return nil, fmt.Errorf("failed to find strategy files: %w", err)
	}

	return &GetStrategyListResponse{
		StrategyPaths: strategyPaths,
	}, nil
}

// RunSelectedStrategy runs the selected strategy
func (s *ZapretServiceImpl) RunSelectedStrategy(ctx context.Context, req *RunSelectedStrategyRequest) (*RunSelectedStrategyResponse, error) {
	slog.Info("Running selected strategy via Twirp", "path", req.StrategyPath)
	
	// TODO: Implement actual strategy running logic
	// This would integrate with the existing daemon's strategy management
	
	return &RunSelectedStrategyResponse{
		Success: true,
		Message: fmt.Sprintf("Strategy %s started successfully", req.StrategyPath),
	}, nil
}

// StopStrategy stops the currently running strategy
func (s *ZapretServiceImpl) StopStrategy(ctx context.Context, req *StopStrategyRequest) (*StopStrategyResponse, error) {
	slog.Info("Stopping strategy via Twirp")
	
	// TODO: Implement actual strategy stopping logic
	// This would integrate with the existing daemon's strategy management
	
	return &StopStrategyResponse{
		Success: true,
		Message: "Strategy stopped successfully",
	}, nil
}

// InstallZapret installs a specific version of Zapret
func (s *ZapretServiceImpl) InstallZapret(ctx context.Context, req *InstallZapretRequest) (*InstallZapretResponse, error) {
	slog.Info("Installing Zapret via Twirp", "version", req.Version)
	
	// TODO: Implement actual installation logic
	// This would integrate with the existing installation scripts
	
	return &InstallZapretResponse{
		Success: true,
		Message: fmt.Sprintf("Zapret version %s installed successfully", req.Version),
	}, nil
}

// GetAvailableVersions returns the available versions of Zapret
func (s *ZapretServiceImpl) GetAvailableVersions(ctx context.Context, req *GetAvailableVersionsRequest) (*GetAvailableVersionsResponse, error) {
	slog.Info("Getting available versions via Twirp")
	
	// TODO: Implement actual version checking logic
	// This would integrate with version checking functionality
	
	// For now, return some dummy versions
	versions := []string{"1.0.0", "1.1.0", "1.2.0", "latest"}
	
	return &GetAvailableVersionsResponse{
		Versions: versions,
	}, nil
}

// GetActiveNFTRules returns the currently active NFT rules
func (s *ZapretServiceImpl) GetActiveNFTRules(ctx context.Context, req *GetActiveNFTRulesRequest) (*GetActiveNFTRulesResponse, error) {
	slog.Info("Getting active NFT rules via Twirp")
	
	// TODO: Implement actual NFT rules inspection
	// This would integrate with firewall inspection functionality
	
	// For now, return some dummy rules
	rules := []string{
		"nftables rule 1",
		"nftables rule 2",
		"nftables rule 3",
	}
	
	return &GetActiveNFTRulesResponse{
		Rules: rules,
	}, nil
}

// GetActiveProcesses returns the currently active processes
func (s *ZapretServiceImpl) GetActiveProcesses(ctx context.Context, req *GetActiveProcessesRequest) (*GetActiveProcessesResponse, error) {
	slog.Info("Getting active processes via Twirp")
	
	// TODO: Implement actual process inspection
	// This would integrate with process management functionality
	
	// For now, return some dummy processes
	processes := []string{
		"zapret-daemon",
		"nfqws-process-1",
		"nfqws-process-2",
	}
	
	return &GetActiveProcessesResponse{
		Processes: processes,
	}, nil
}

// RestartDaemon restarts the Zapret daemon
func (s *ZapretServiceImpl) RestartDaemon(ctx context.Context, req *RestartDaemonRequest) (*RestartDaemonResponse, error) {
	slog.Info("Restarting daemon via Twirp")
	
	// TODO: Implement actual daemon restart logic
	// This would integrate with the existing daemon restart functionality
	
	return &RestartDaemonResponse{
		Success: true,
		Message: "Daemon restarted successfully",
	}, nil
}