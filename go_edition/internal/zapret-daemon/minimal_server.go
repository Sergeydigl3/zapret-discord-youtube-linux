// Package twirp provides Twirp-based RPC service for Zapret
package twirp

import (
	"fmt"
	"net/http"
)

// MinimalServer implements a minimal Twirp server following best practices
type MinimalServer struct {
	service ZapretService
	server  *http.Server
	port    int
}

// NewMinimalServer creates a new minimal Twirp server
type MinimalServerOption func(*MinimalServer)

func WithMinimalPort(port int) MinimalServerOption {
	return func(s *MinimalServer) {
		s.port = port
	}
}

func NewMinimalServer(service ZapretService, opts ...MinimalServerOption) *MinimalServer {
	server := &MinimalServer{
		service: service,
		port:    8080, // default port
	}

	for _, opt := range opts {
		opt(server)
	}

	return server
}

// Start starts the HTTP server
func (s *MinimalServer) Start() error {
	s.server = &http.Server{
		Addr:    fmt.Sprintf(":%d", s.port),
		Handler: s,
	}

	go func() {
		fmt.Printf("Twirp server listening on port %d\n", s.port)
		if err := s.server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			fmt.Printf("Twirp server error: %v\n", err)
		}
	}()

	return nil
}

// Stop stops the HTTP server
func (s *MinimalServer) Stop() error {
	if s.server != nil {
		return s.server.Close()
	}
	return nil
}

// ServeHTTP implements http.Handler interface
func (s *MinimalServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// Use the existing Server implementation
	server := NewServer(s.service)
	// For now, just delegate to the existing server
	// In a real implementation, we would use twirp.NewServer() here
	server.ServeHTTP(w, r)
}