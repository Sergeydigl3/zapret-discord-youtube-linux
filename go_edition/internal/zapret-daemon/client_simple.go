// Package twirp provides Twirp-based RPC service for Zapret
package twirp

import (
	"context"
)

// SimpleClient provides a Twirp client for the Zapret service using generated code
type SimpleClient struct {
	client ZapretService
}

// NewSimpleClient creates a new Twirp client using generated code
func NewSimpleClient(baseURL string) *SimpleClient {
	// Create Twirp client using the existing Server implementation
	client := NewServer(NewZapretServiceImpl())
	
	return &SimpleClient{
		client: client,
	}
}

// GetStrategyList calls the GetStrategyList RPC method
func (c *SimpleClient) GetStrategyList(ctx context.Context) (*GetStrategyListResponse, error) {
	return c.client.GetStrategyList(ctx, &GetStrategyListRequest{})
}

// RunSelectedStrategy calls the RunSelectedStrategy RPC method
func (c *SimpleClient) RunSelectedStrategy(ctx context.Context, strategyPath string) (*RunSelectedStrategyResponse, error) {
	return c.client.RunSelectedStrategy(ctx, &RunSelectedStrategyRequest{
		StrategyPath: strategyPath,
	})
}

// StopStrategy calls the StopStrategy RPC method
func (c *SimpleClient) StopStrategy(ctx context.Context) (*StopStrategyResponse, error) {
	return c.client.StopStrategy(ctx, &StopStrategyRequest{})
}

// InstallZapret calls the InstallZapret RPC method
func (c *SimpleClient) InstallZapret(ctx context.Context, version string) (*InstallZapretResponse, error) {
	return c.client.InstallZapret(ctx, &InstallZapretRequest{
		Version: version,
	})
}

// GetAvailableVersions calls the GetAvailableVersions RPC method
func (c *SimpleClient) GetAvailableVersions(ctx context.Context) (*GetAvailableVersionsResponse, error) {
	return c.client.GetAvailableVersions(ctx, &GetAvailableVersionsRequest{})
}

// GetActiveNFTRules calls the GetActiveNFTRules RPC method
func (c *SimpleClient) GetActiveNFTRules(ctx context.Context) (*GetActiveNFTRulesResponse, error) {
	return c.client.GetActiveNFTRules(ctx, &GetActiveNFTRulesRequest{})
}

// GetActiveProcesses calls the GetActiveProcesses RPC method
func (c *SimpleClient) GetActiveProcesses(ctx context.Context) (*GetActiveProcessesResponse, error) {
	return c.client.GetActiveProcesses(ctx, &GetActiveProcessesRequest{})
}

// RestartDaemon calls the RestartDaemon RPC method
func (c *SimpleClient) RestartDaemon(ctx context.Context) (*RestartDaemonResponse, error) {
	return c.client.RestartDaemon(ctx, &RestartDaemonRequest{})
}
