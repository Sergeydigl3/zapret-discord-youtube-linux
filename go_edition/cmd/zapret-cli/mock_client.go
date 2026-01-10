package main

import (
	"context"
	"fmt"

	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/zapret-daemon"
)

// MockZapretServiceClient is a mock implementation for testing
type MockZapretServiceClient struct{}

// GetStrategyList implements ZapretServiceClient
func (m *MockZapretServiceClient) GetStrategyList(ctx context.Context, req *zapretdaemon.GetStrategyListRequest) (*zapretdaemon.GetStrategyListResponse, error) {
	return &zapretdaemon.GetStrategyListResponse{
		StrategyPaths: []string{"default.bat", "custom.bat"},
	}, nil
}

// RunSelectedStrategy implements ZapretServiceClient
func (m *MockZapretServiceClient) RunSelectedStrategy(ctx context.Context, req *zapretdaemon.RunSelectedStrategyRequest) (*zapretdaemon.RunSelectedStrategyResponse, error) {
	return &zapretdaemon.RunSelectedStrategyResponse{
		Success: true,
		Message: fmt.Sprintf("Strategy %s started successfully", req.StrategyPath),
	}, nil
}

// StopStrategy implements ZapretServiceClient
func (m *MockZapretServiceClient) StopStrategy(ctx context.Context, req *zapretdaemon.StopStrategyRequest) (*zapretdaemon.StopStrategyResponse, error) {
	return &zapretdaemon.StopStrategyResponse{
		Success: true,
		Message: "Strategy stopped successfully",
	}, nil
}

// InstallZapret implements ZapretServiceClient
func (m *MockZapretServiceClient) InstallZapret(ctx context.Context, req *zapretdaemon.InstallZapretRequest) (*zapretdaemon.InstallZapretResponse, error) {
	return &zapretdaemon.InstallZapretResponse{
		Success: true,
		Message: "Zapret installed successfully",
	}, nil
}

// GetAvailableVersions implements ZapretServiceClient
func (m *MockZapretServiceClient) GetAvailableVersions(ctx context.Context, req *zapretdaemon.GetAvailableVersionsRequest) (*zapretdaemon.GetAvailableVersionsResponse, error) {
	return &zapretdaemon.GetAvailableVersionsResponse{
		Versions: []string{"1.0.0", "1.1.0", "latest"},
	}, nil
}

// GetActiveNFTRules implements ZapretServiceClient
func (m *MockZapretServiceClient) GetActiveNFTRules(ctx context.Context, req *zapretdaemon.GetActiveNFTRulesRequest) (*zapretdaemon.GetActiveNFTRulesResponse, error) {
	return &zapretdaemon.GetActiveNFTRulesResponse{
		Rules: []string{"rule1", "rule2", "rule3"},
	}, nil
}

// GetActiveProcesses implements ZapretServiceClient
func (m *MockZapretServiceClient) GetActiveProcesses(ctx context.Context, req *zapretdaemon.GetActiveProcessesRequest) (*zapretdaemon.GetActiveProcessesResponse, error) {
	return &zapretdaemon.GetActiveProcessesResponse{
		Processes: []string{"process1", "process2"},
	}, nil
}

// RestartDaemon implements ZapretServiceClient
func (m *MockZapretServiceClient) RestartDaemon(ctx context.Context, req *zapretdaemon.RestartDaemonRequest) (*zapretdaemon.RestartDaemonResponse, error) {
	return &zapretdaemon.RestartDaemonResponse{
		Success: true,
		Message: "Daemon restarted successfully",
	}, nil
}

// NewMockZapretServiceClient creates a new mock client
func NewMockZapretServiceClient() *MockZapretServiceClient {
	return &MockZapretServiceClient{}
}