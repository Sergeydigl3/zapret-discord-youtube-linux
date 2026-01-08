// Package twirp provides Twirp-based RPC service for Zapret
package twirp

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

// Client provides a Twirp client for the Zapret service
type Client struct {
	baseURL string
	client  *http.Client
}

// NewClient creates a new Twirp client
func NewClient(baseURL string) *Client {
	return &Client{
		baseURL: baseURL,
		client:  &http.Client{},
	}
}

// GetStrategyList calls the GetStrategyList RPC method
func (c *Client) GetStrategyList(ctx context.Context) (*GetStrategyListResponse, error) {
	req := &GetStrategyListRequest{}
	var resp GetStrategyListResponse
	
	if err := c.callRPC(ctx, "zapret.twirp.ZapretService/GetStrategyList", req, &resp); err != nil {
		return nil, err
	}
	
	return &resp, nil
}

// RunSelectedStrategy calls the RunSelectedStrategy RPC method
func (c *Client) RunSelectedStrategy(ctx context.Context, strategyPath string) (*RunSelectedStrategyResponse, error) {
	req := &RunSelectedStrategyRequest{StrategyPath: strategyPath}
	var resp RunSelectedStrategyResponse
	
	if err := c.callRPC(ctx, "zapret.twirp.ZapretService/RunSelectedStrategy", req, &resp); err != nil {
		return nil, err
	}
	
	return &resp, nil
}

// StopStrategy calls the StopStrategy RPC method
func (c *Client) StopStrategy(ctx context.Context) (*StopStrategyResponse, error) {
	req := &StopStrategyRequest{}
	var resp StopStrategyResponse
	
	if err := c.callRPC(ctx, "zapret.twirp.ZapretService/StopStrategy", req, &resp); err != nil {
		return nil, err
	}
	
	return &resp, nil
}

// InstallZapret calls the InstallZapret RPC method
func (c *Client) InstallZapret(ctx context.Context, version string) (*InstallZapretResponse, error) {
	req := &InstallZapretRequest{Version: version}
	var resp InstallZapretResponse
	
	if err := c.callRPC(ctx, "zapret.twirp.ZapretService/InstallZapret", req, &resp); err != nil {
		return nil, err
	}
	
	return &resp, nil
}

// GetAvailableVersions calls the GetAvailableVersions RPC method
func (c *Client) GetAvailableVersions(ctx context.Context) (*GetAvailableVersionsResponse, error) {
	req := &GetAvailableVersionsRequest{}
	var resp GetAvailableVersionsResponse
	
	if err := c.callRPC(ctx, "zapret.twirp.ZapretService/GetAvailableVersions", req, &resp); err != nil {
		return nil, err
	}
	
	return &resp, nil
}

// GetActiveNFTRules calls the GetActiveNFTRules RPC method
func (c *Client) GetActiveNFTRules(ctx context.Context) (*GetActiveNFTRulesResponse, error) {
	req := &GetActiveNFTRulesRequest{}
	var resp GetActiveNFTRulesResponse
	
	if err := c.callRPC(ctx, "zapret.twirp.ZapretService/GetActiveNFTRules", req, &resp); err != nil {
		return nil, err
	}
	
	return &resp, nil
}

// GetActiveProcesses calls the GetActiveProcesses RPC method
func (c *Client) GetActiveProcesses(ctx context.Context) (*GetActiveProcessesResponse, error) {
	req := &GetActiveProcessesRequest{}
	var resp GetActiveProcessesResponse
	
	if err := c.callRPC(ctx, "zapret.twirp.ZapretService/GetActiveProcesses", req, &resp); err != nil {
		return nil, err
	}
	
	return &resp, nil
}

// RestartDaemon calls the RestartDaemon RPC method
func (c *Client) RestartDaemon(ctx context.Context) (*RestartDaemonResponse, error) {
	req := &RestartDaemonRequest{}
	var resp RestartDaemonResponse
	
	if err := c.callRPC(ctx, "zapret.twirp.ZapretService/RestartDaemon", req, &resp); err != nil {
		return nil, err
	}
	
	return &resp, nil
}

// callRPC makes a generic Twirp RPC call
func (c *Client) callRPC(ctx context.Context, method string, req interface{}, resp interface{}) error {
	url := fmt.Sprintf("%s/%s", c.baseURL, method)
	
	// Marshal request
	reqBody, err := json.Marshal(req)
	if err != nil {
		return fmt.Errorf("failed to marshal request: %w", err)
	}
	
	// Create HTTP request
	httpReq, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(reqBody))
	if err != nil {
		return fmt.Errorf("failed to create HTTP request: %w", err)
	}
	
	// Set headers
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Accept", "application/json")
	
	// Make request
	httpResp, err := c.client.Do(httpReq)
	if err != nil {
		return fmt.Errorf("failed to make HTTP request: %w", err)
	}
	defer httpResp.Body.Close()
	
	// Check status code
	if httpResp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(httpResp.Body)
		return fmt.Errorf("RPC failed with status %d: %s", httpResp.StatusCode, string(body))
	}
	
	// Decode response
	if err := json.NewDecoder(httpResp.Body).Decode(resp); err != nil {
		return fmt.Errorf("failed to decode response: %w", err)
	}
	
	return nil
}