// Package twirp provides Twirp-based RPC client for Zapret CLI
package twirp

import (
	"context"
	"fmt"
	"net/http"
	"os"

	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/zapret-daemon"
	"github.com/twitchtv/twirp"
)

// ZapretServiceClient is the client API for ZapretService service.
type ZapretServiceClient interface {
	GetStrategyList(context.Context, *zapretdaemon.GetStrategyListRequest) (*zapretdaemon.GetStrategyListResponse, error)
	RunSelectedStrategy(context.Context, *zapretdaemon.RunSelectedStrategyRequest) (*zapretdaemon.RunSelectedStrategyResponse, error)
	StopStrategy(context.Context, *zapretdaemon.StopStrategyRequest) (*zapretdaemon.StopStrategyResponse, error)
	InstallZapret(context.Context, *zapretdaemon.InstallZapretRequest) (*zapretdaemon.InstallZapretResponse, error)
	GetAvailableVersions(context.Context, *zapretdaemon.GetAvailableVersionsRequest) (*zapretdaemon.GetAvailableVersionsResponse, error)
	GetActiveNFTRules(context.Context, *zapretdaemon.GetActiveNFTRulesRequest) (*zapretdaemon.GetActiveNFTRulesResponse, error)
	GetActiveProcesses(context.Context, *zapretdaemon.GetActiveProcessesRequest) (*zapretdaemon.GetActiveProcessesResponse, error)
	RestartDaemon(context.Context, *zapretdaemon.RestartDaemonRequest) (*zapretdaemon.RestartDaemonResponse, error)
}

// client implements ZapretServiceClient.
type client struct {
	client *http.Client
	baseURL string
}

// NewZapretServiceProtobufClient creates a new ZapretService client.
func NewZapretServiceProtobufClient(baseURL string, httpClient *http.Client) ZapretServiceClient {
	if httpClient == nil {
		httpClient = http.DefaultClient
	}
	return &client{
		client:  httpClient,
		baseURL: baseURL,
	}
}

// GetStrategyList implements ZapretServiceClient.
func (c *client) GetStrategyList(ctx context.Context, req *zapretdaemon.GetStrategyListRequest) (*zapretdaemon.GetStrategyListResponse, error) {
	url := fmt.Sprintf("%s/twirp/zapret.twirp.ZapretService/GetStrategyList", c.baseURL)
	
	var response zapretdaemon.GetStrategyListResponse
	err := twirp.NewClient(c.serviceName(), url, c.client).Call(ctx, req, &response)
	if err != nil {
		return nil, fmt.Errorf("failed to get strategy list: %w", err)
	}
	
	return &response, nil
}

// RunSelectedStrategy implements ZapretServiceClient.
func (c *client) RunSelectedStrategy(ctx context.Context, req *zapretdaemon.RunSelectedStrategyRequest) (*zapretdaemon.RunSelectedStrategyResponse, error) {
	url := fmt.Sprintf("%s/twirp/zapret.twirp.ZapretService/RunSelectedStrategy", c.baseURL)
	
	var response zapretdaemon.RunSelectedStrategyResponse
	err := twirp.NewClient(c.serviceName(), url, c.client).Call(ctx, req, &response)
	if err != nil {
		return nil, fmt.Errorf("failed to run selected strategy: %w", err)
	}
	
	return &response, nil
}

// StopStrategy implements ZapretServiceClient.
func (c *client) StopStrategy(ctx context.Context, req *zapretdaemon.StopStrategyRequest) (*zapretdaemon.StopStrategyResponse, error) {
	url := fmt.Sprintf("%s/twirp/zapret.twirp.ZapretService/StopStrategy", c.baseURL)
	
	var response zapretdaemon.StopStrategyResponse
	err := twirp.NewClient(c.serviceName(), url, c.client).Call(ctx, req, &response)
	if err != nil {
		return nil, fmt.Errorf("failed to stop strategy: %w", err)
	}
	
	return &response, nil
}

// InstallZapret implements ZapretServiceClient.
func (c *client) InstallZapret(ctx context.Context, req *zapretdaemon.InstallZapretRequest) (*zapretdaemon.InstallZapretResponse, error) {
	url := fmt.Sprintf("%s/twirp/zapret.twirp.ZapretService/InstallZapret", c.baseURL)
	
	var response zapretdaemon.InstallZapretResponse
	err := twirp.NewClient(c.serviceName(), url, c.client).Call(ctx, req, &response)
	if err != nil {
		return nil, fmt.Errorf("failed to install zapret: %w", err)
	}
	
	return &response, nil
}

// GetAvailableVersions implements ZapretServiceClient.
func (c *client) GetAvailableVersions(ctx context.Context, req *zapretdaemon.GetAvailableVersionsRequest) (*zapretdaemon.GetAvailableVersionsResponse, error) {
	url := fmt.Sprintf("%s/twirp/zapret.twirp.ZapretService/GetAvailableVersions", c.baseURL)
	
	var response zapretdaemon.GetAvailableVersionsResponse
	err := twirp.NewClient(c.serviceName(), url, c.client).Call(ctx, req, &response)
	if err != nil {
		return nil, fmt.Errorf("failed to get available versions: %w", err)
	}
	
	return &response, nil
}

// GetActiveNFTRules implements ZapretServiceClient.
func (c *client) GetActiveNFTRules(ctx context.Context, req *zapretdaemon.GetActiveNFTRulesRequest) (*zapretdaemon.GetActiveNFTRulesResponse, error) {
	url := fmt.Sprintf("%s/twirp/zapret.twirp.ZapretService/GetActiveNFTRules", c.baseURL)
	
	var response zapretdaemon.GetActiveNFTRulesResponse
	err := twirp.NewClient(c.serviceName(), url, c.client).Call(ctx, req, &response)
	if err != nil {
		return nil, fmt.Errorf("failed to get active NFT rules: %w", err)
	}
	
	return &response, nil
}

// GetActiveProcesses implements ZapretServiceClient.
func (c *client) GetActiveProcesses(ctx context.Context, req *zapretdaemon.GetActiveProcessesRequest) (*zapretdaemon.GetActiveProcessesResponse, error) {
	url := fmt.Sprintf("%s/twirp/zapret.twirp.ZapretService/GetActiveProcesses", c.baseURL)
	
	var response zapretdaemon.GetActiveProcessesResponse
	err := twirp.NewClient(c.serviceName(), url, c.client).Call(ctx, req, &response)
	if err != nil {
		return nil, fmt.Errorf("failed to get active processes: %w", err)
	}
	
	return &response, nil
}

// RestartDaemon implements ZapretServiceClient.
func (c *client) RestartDaemon(ctx context.Context, req *zapretdaemon.RestartDaemonRequest) (*zapretdaemon.RestartDaemonResponse, error) {
	url := fmt.Sprintf("%s/twirp/zapret.twirp.ZapretService/RestartDaemon", c.baseURL)
	
	var response zapretdaemon.RestartDaemonResponse
	err := twirp.NewClient(c.serviceName(), url, c.client).Call(ctx, req, &response)
	if err != nil {
		return nil, fmt.Errorf("failed to restart daemon: %w", err)
	}
	
	return &response, nil
}

// serviceName returns the service name for Twirp client
func (c *client) serviceName() string {
	return "zapret.twirp.ZapretService"
}

// NewZapretServiceJSONClient creates a new ZapretService client using JSON encoding
func NewZapretServiceJSONClient(baseURL string, httpClient *http.Client) ZapretServiceClient {
	return NewZapretServiceProtobufClient(baseURL, httpClient)
}

// GetSocketPath returns the socket path from environment or uses default
func GetSocketPath() string {
	if socketPath := os.Getenv("ZAPRET_SOCKET_PATH"); socketPath != "" {
		return socketPath
	}
	return GetDefaultSocketPath()
}