// Package twirp provides Twirp-based RPC service for Zapret
package twirp

import (
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"

	zapretdaemon "github.com/sergeydigl3/zapret-discord-youtube-go/internal/zapret-daemon"
	"github.com/twitchtv/twirp"
)

// TwirpServer wraps the ZapretService implementation
type TwirpServer struct {
	service zapretdaemon.ZapretService
	server  *http.Server
	port    int
	mux     *http.ServeMux
	socketPath string
	listener net.Listener
}

// NewTwirpServer creates a new Twirp server
type TwirpServerOption func(*TwirpServer)

func WithSocketPath(path string) TwirpServerOption {
	return func(s *TwirpServer) {
		s.socketPath = path
	}
}

func WithPort(port int) TwirpServerOption {
	return func(s *TwirpServer) {
		s.port = port
	}
}

func NewTwirpServer(service zapretdaemon.ZapretService, opts ...TwirpServerOption) *TwirpServer {
	server := &TwirpServer{
		service: service,
		port:    8080, // default port
		mux:     http.NewServeMux(),
	}

	for _, opt := range opts {
		opt(server)
	}

	return server
}

// GetDefaultSocketPath returns the default socket path
func GetDefaultSocketPath() string {
	// Try to get from environment variable first
	if socketPath := os.Getenv("ZAPRET_SOCKET_PATH"); socketPath != "" {
		return socketPath
	}

	// Default path
	return "/var/run/zapret.sock"
}

// EnsureSocketDirectory ensures the directory for the socket exists
func EnsureSocketDirectory(socketPath string) error {
	dir := filepath.Dir(socketPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create socket directory %s: %w", dir, err)
	}
	return nil
}

// Start starts the Twirp server (HTTP or Unix socket)
func (s *TwirpServer) Start() error {
	// Register Twirp handlers
	s.mux.Handle("/twirp/zapret.twirp.ZapretService/GetStrategyList",
		http.HandlerFunc(s.handleGetStrategyList))
	s.mux.Handle("/twirp/zapret.twirp.ZapretService/RunSelectedStrategy",
		http.HandlerFunc(s.handleRunSelectedStrategy))
	s.mux.Handle("/twirp/zapret.twirp.ZapretService/StopStrategy",
		http.HandlerFunc(s.handleStopStrategy))
	s.mux.Handle("/twirp/zapret.twirp.ZapretService/InstallZapret",
		http.HandlerFunc(s.handleInstallZapret))
	s.mux.Handle("/twirp/zapret.twirp.ZapretService/GetAvailableVersions",
		http.HandlerFunc(s.handleGetAvailableVersions))
	s.mux.Handle("/twirp/zapret.twirp.ZapretService/GetActiveNFTRules",
		http.HandlerFunc(s.handleGetActiveNFTRules))
	s.mux.Handle("/twirp/zapret.twirp.ZapretService/GetActiveProcesses",
		http.HandlerFunc(s.handleGetActiveProcesses))
	s.mux.Handle("/twirp/zapret.twirp.ZapretService/RestartDaemon",
		http.HandlerFunc(s.handleRestartDaemon))

	// Use Unix socket if socket path is provided
	if s.socketPath != "" {
		return s.startUnixSocket()
	}

	// Otherwise use HTTP
	s.server = &http.Server{
		Addr:    fmt.Sprintf(":%d", s.port),
		Handler: s.mux,
	}

	go func() {
		fmt.Printf("Twirp server listening on port %d\n", s.port)
		if err := s.server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			fmt.Printf("Twirp server error: %v\n", err)
		}
	}()

	return nil
}

// startUnixSocket starts the Twirp server using Unix socket
func (s *TwirpServer) startUnixSocket() error {
	// Ensure socket directory exists
	if err := EnsureSocketDirectory(s.socketPath); err != nil {
		return fmt.Errorf("failed to ensure socket directory: %w", err)
	}

	// Remove existing socket if present
	if _, err := os.Stat(s.socketPath); err == nil {
		if err := os.Remove(s.socketPath); err != nil {
			return fmt.Errorf("failed to remove existing socket: %w", err)
		}
	}

	// Create Unix socket listener
	var err error
	s.listener, err = net.Listen("unix", s.socketPath)
	if err != nil {
		return fmt.Errorf("failed to listen on Unix socket: %w", err)
	}

	// Set permissions on socket
	if err := os.Chmod(s.socketPath, 0666); err != nil {
		return fmt.Errorf("failed to set socket permissions: %w", err)
	}

	s.server = &http.Server{
		Handler: s.mux,
	}

	go func() {
		fmt.Printf("Twirp server listening on Unix socket %s\n", s.socketPath)
		if err := s.server.Serve(s.listener); err != nil && err != http.ErrServerClosed {
			fmt.Printf("Twirp server error: %v\n", err)
		}
	}()

	return nil
}

// Stop stops the Twirp server
func (s *TwirpServer) Stop() error {
	if s.server != nil {
		return s.server.Close()
	}
	return nil
}

// GetSocketPath returns the socket path if using Unix socket
func (s *TwirpServer) GetSocketPath() string {
	return s.socketPath
}

// Handler functions
func (s *TwirpServer) handleGetStrategyList(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	
	// For now, just return dummy data
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"strategy_paths":["strategy1.bat","strategy2.bat"]}`))
}

func (s *TwirpServer) handleRunSelectedStrategy(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	
	// TODO: Parse request and call service
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"success":true,"message":"Strategy started"}`))
}

func (s *TwirpServer) handleStopStrategy(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	
	// TODO: Call service
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"success":true,"message":"Strategy stopped"}`))
}

func (s *TwirpServer) handleInstallZapret(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	
	// TODO: Parse request and call service
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"success":true,"message":"Zapret installed"}`))
}

func (s *TwirpServer) handleGetAvailableVersions(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	
	// TODO: Call service
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"versions":["1.0.0","1.1.0","latest"]}`))
}

func (s *TwirpServer) handleGetActiveNFTRules(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	
	// TODO: Call service
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"rules":["rule1","rule2"]}`))
}

func (s *TwirpServer) handleGetActiveProcesses(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	
	// TODO: Call service
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"processes":["process1","process2"]}`))
}

func (s *TwirpServer) handleRestartDaemon(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	
	// TODO: Call service
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"success":true,"message":"Daemon restarted"}`))
}