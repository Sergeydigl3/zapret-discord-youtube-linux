// Package twirp provides Twirp-based RPC service for Zapret
package twirp

import (
	"fmt"
	"net/http"
)

// SimpleTwirpServer wraps the ZapretService implementation using generated code
type SimpleTwirpServer struct {
	service ZapretService
	server  *http.Server
	port    int
}

// NewSimpleTwirpServer creates a new Twirp server using generated code
type SimpleTwirpServerOption func(*SimpleTwirpServer)

func WithSimplePort(port int) SimpleTwirpServerOption {
	return func(s *SimpleTwirpServer) {
		s.port = port
	}
}

func NewSimpleTwirpServer(service ZapretService, opts ...SimpleTwirpServerOption) *SimpleTwirpServer {
	server := &SimpleTwirpServer{
		service: service,
		port:    8080, // default port
	}

	for _, opt := range opts {
		opt(server)
	}

	return server
}

// Start starts the Twirp HTTP server using generated handlers
func (s *SimpleTwirpServer) Start() error {
	// Create a new Server that implements the generated ZapretServiceServer interface
	server := NewServer(s.service)

	// Create HTTP server with the Twirp handler
	s.server = &http.Server{
		Addr:    fmt.Sprintf(":%d", s.port),
		Handler: server,
	}

	go func() {
		fmt.Printf("Twirp server listening on port %d\n", s.port)
		if err := s.server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			fmt.Printf("Twirp server error: %v\n", err)
		}
	}()

	return nil
}

// Stop stops the Twirp HTTP server
func (s *SimpleTwirpServer) Stop() error {
	if s.server != nil {
		return s.server.Close()
	}
	return nil
}
