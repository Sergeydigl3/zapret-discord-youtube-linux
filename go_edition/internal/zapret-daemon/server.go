// Package twirp provides Twirp-based RPC service for Zapret
package twirp

import (
	"context"
	"fmt"
	"net/http"

	"github.com/twitchtv/twirp"
)

// ZapretService defines the Twirp service interface
type ZapretService interface {
	// Strategies functionality
	GetStrategyList(ctx context.Context, req *GetStrategyListRequest) (*GetStrategyListResponse, error)
	RunSelectedStrategy(ctx context.Context, req *RunSelectedStrategyRequest) (*RunSelectedStrategyResponse, error)
	StopStrategy(ctx context.Context, req *StopStrategyRequest) (*StopStrategyResponse, error)

	// Requirements functionality
	InstallZapret(ctx context.Context, req *InstallZapretRequest) (*InstallZapretResponse, error)
	GetAvailableVersions(ctx context.Context, req *GetAvailableVersionsRequest) (*GetAvailableVersionsResponse, error)

	// Debug functionality
	GetActiveNFTRules(ctx context.Context, req *GetActiveNFTRulesRequest) (*GetActiveNFTRulesResponse, error)
	GetActiveProcesses(ctx context.Context, req *GetActiveProcessesRequest) (*GetActiveProcessesResponse, error)

	// Daemon control
	RestartDaemon(ctx context.Context, req *RestartDaemonRequest) (*RestartDaemonResponse, error)
}

// Strategy messages
type GetStrategyListRequest struct {
}

type GetStrategyListResponse struct {
	StrategyPaths []string `json:"strategy_paths"`
}

type RunSelectedStrategyRequest struct {
	StrategyPath string `json:"strategy_path"`
}

type RunSelectedStrategyResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
}

type StopStrategyRequest struct {
}

type StopStrategyResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
}

// Requirements messages
type InstallZapretRequest struct {
	Version string `json:"version"`
}

type InstallZapretResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
}

type GetAvailableVersionsRequest struct {
}

type GetAvailableVersionsResponse struct {
	Versions []string `json:"versions"`
}

// Debug messages
type GetActiveNFTRulesRequest struct {
}

type GetActiveNFTRulesResponse struct {
	Rules []string `json:"rules"`
}

type GetActiveProcessesRequest struct {
}

type GetActiveProcessesResponse struct {
	Processes []string `json:"processes"`
}

// Daemon control messages
type RestartDaemonRequest struct {
}

type RestartDaemonResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
}

// Server implements the Twirp service interface
type Server struct {
	service ZapretService
}

func NewServer(service ZapretService) *Server {
	return &Server{service: service}
}

// ServeHTTP implements http.Handler interface
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// Simple routing based on path
	switch r.URL.Path {
	case "/twirp/zapret.twirp.ZapretService/GetStrategyList":
		s.handleGetStrategyList(w, r)
	case "/twirp/zapret.twirp.ZapretService/RunSelectedStrategy":
		s.handleRunSelectedStrategy(w, r)
	case "/twirp/zapret.twirp.ZapretService/StopStrategy":
		s.handleStopStrategy(w, r)
	case "/twirp/zapret.twirp.ZapretService/InstallZapret":
		s.handleInstallZapret(w, r)
	case "/twirp/zapret.twirp.ZapretService/GetAvailableVersions":
		s.handleGetAvailableVersions(w, r)
	case "/twirp/zapret.twirp.ZapretService/GetActiveNFTRules":
		s.handleGetActiveNFTRules(w, r)
	case "/twirp/zapret.twirp.ZapretService/GetActiveProcesses":
		s.handleGetActiveProcesses(w, r)
	case "/twirp/zapret.twirp.ZapretService/RestartDaemon":
		s.handleRestartDaemon(w, r)
	default:
		http.NotFound(w, r)
	}
}

// Handler functions
func (s *Server) handleGetStrategyList(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	
	resp, err := s.service.GetStrategyList(r.Context(), &GetStrategyListRequest{})
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(fmt.Sprintf(`{"strategy_paths":%v}`, resp.StrategyPaths)))
}

func (s *Server) handleRunSelectedStrategy(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	
	resp, err := s.service.RunSelectedStrategy(r.Context(), &RunSelectedStrategyRequest{})
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(fmt.Sprintf(`{"success":%v,"message":"%s"}`, resp.Success, resp.Message)))
}

func (s *Server) handleStopStrategy(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	
	resp, err := s.service.StopStrategy(r.Context(), &StopStrategyRequest{})
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(fmt.Sprintf(`{"success":%v,"message":"%s"}`, resp.Success, resp.Message)))
}

func (s *Server) handleInstallZapret(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	
	resp, err := s.service.InstallZapret(r.Context(), &InstallZapretRequest{})
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(fmt.Sprintf(`{"success":%v,"message":"%s"}`, resp.Success, resp.Message)))
}

func (s *Server) handleGetAvailableVersions(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	
	resp, err := s.service.GetAvailableVersions(r.Context(), &GetAvailableVersionsRequest{})
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(fmt.Sprintf(`{"versions":%v}`, resp.Versions)))
}

func (s *Server) handleGetActiveNFTRules(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	
	resp, err := s.service.GetActiveNFTRules(r.Context(), &GetActiveNFTRulesRequest{})
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(fmt.Sprintf(`{"rules":%v}`, resp.Rules)))
}

func (s *Server) handleGetActiveProcesses(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	
	resp, err := s.service.GetActiveProcesses(r.Context(), &GetActiveProcessesRequest{})
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(fmt.Sprintf(`{"processes":%v}`, resp.Processes)))
}

func (s *Server) handleRestartDaemon(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	
	resp, err := s.service.RestartDaemon(r.Context(), &RestartDaemonRequest{})
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(fmt.Sprintf(`{"success":%v,"message":"%s"}`, resp.Success, resp.Message)))
}


// GetStrategyList implements the GetStrategyList RPC method
func (s *Server) GetStrategyList(ctx context.Context, req *GetStrategyListRequest) (*GetStrategyListResponse, error) {
	return s.service.GetStrategyList(ctx, req)
}

// RunSelectedStrategy implements the RunSelectedStrategy RPC method
func (s *Server) RunSelectedStrategy(ctx context.Context, req *RunSelectedStrategyRequest) (*RunSelectedStrategyResponse, error) {
	return s.service.RunSelectedStrategy(ctx, req)
}

// StopStrategy implements the StopStrategy RPC method
func (s *Server) StopStrategy(ctx context.Context, req *StopStrategyRequest) (*StopStrategyResponse, error) {
	return s.service.StopStrategy(ctx, req)
}

// InstallZapret implements the InstallZapret RPC method
func (s *Server) InstallZapret(ctx context.Context, req *InstallZapretRequest) (*InstallZapretResponse, error) {
	return s.service.InstallZapret(ctx, req)
}

// GetAvailableVersions implements the GetAvailableVersions RPC method
func (s *Server) GetAvailableVersions(ctx context.Context, req *GetAvailableVersionsRequest) (*GetAvailableVersionsResponse, error) {
	return s.service.GetAvailableVersions(ctx, req)
}

// GetActiveNFTRules implements the GetActiveNFTRules RPC method
func (s *Server) GetActiveNFTRules(ctx context.Context, req *GetActiveNFTRulesRequest) (*GetActiveNFTRulesResponse, error) {
	return s.service.GetActiveNFTRules(ctx, req)
}

// GetActiveProcesses implements the GetActiveProcesses RPC method
func (s *Server) GetActiveProcesses(ctx context.Context, req *GetActiveProcessesRequest) (*GetActiveProcessesResponse, error) {
	return s.service.GetActiveProcesses(ctx, req)
}

// RestartDaemon implements the RestartDaemon RPC method
func (s *Server) RestartDaemon(ctx context.Context, req *RestartDaemonRequest) (*RestartDaemonResponse, error) {
	return s.service.RestartDaemon(ctx, req)
}

// Hooks for Twirp server
func (s *Server) MethodName() string {
	return "ZapretService"
}

func (s *Server) ServiceName() string {
	return "zapret.twirp.ZapretService"
}

// Error handling
func (s *Server) Error(ctx context.Context, twirpError twirp.Error) error {
	return twirpError
}