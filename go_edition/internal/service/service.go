// Package service provides service installation and management functionality
// for the Zapret application. It supports multiple init systems (systemd, openrc, sysvinit).
package service

import (
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"text/template"

	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/errors"
)

const (
	// ServiceName is the name of the system service
	ServiceName = "zapret_discord_youtube"
	// SystemdType is the systemd init system type
	SystemdType = "systemd"
	// OpenRCType is the OpenRC init system type
	OpenRCType = "openrc"
	// SysVinitType is the SysVinit init system type
	SysVinitType = "sysvinit"
)

// Backend interface defines the methods that all service backends must implement
type Backend interface {
	Install() error
	Remove() error
	Start() error
	Stop() error
	Status() error
	Type() string
}

// Manager manages service operations
type Manager struct {
	backend Backend
}

// NewManager creates a new service manager with automatic backend detection
func NewManager() (*Manager, error) {
	exePath, err := os.Executable()
	if err != nil {
		return nil, errors.NewServiceError("", "create", fmt.Sprintf("failed to get executable path: %v", err))
	}

	baseDir := filepath.Dir(exePath)
	configPath := filepath.Join(baseDir, "conf.yml")
	stopScriptPath := filepath.Join(baseDir, "stop_and_clean.sh")

	// Detect available service backend
	backend, err := detectBackend(exePath, configPath, stopScriptPath)
	if err != nil {
		return nil, errors.Wrap(err, "failed to detect service backend")
	}

	slog.Debug("Detected service backend", "backend", backend.Type())

	return &Manager{
		backend: backend,
	}, nil
}

// Install installs the service
func (m *Manager) Install() error {
	slog.Info("Installing service", "backend", m.backend.Type())
	return m.backend.Install()
}

// Remove removes the service
func (m *Manager) Remove() error {
	slog.Info("Removing service", "backend", m.backend.Type())
	return m.backend.Remove()
}

// Start starts the service
func (m *Manager) Start() error {
	slog.Info("Starting service", "backend", m.backend.Type())
	return m.backend.Start()
}

// Stop stops the service
func (m *Manager) Stop() error {
	slog.Info("Stopping service", "backend", m.backend.Type())
	return m.backend.Stop()
}

// Status returns the service status
func (m *Manager) Status() error {
	slog.Info("Checking service status", "backend", m.backend.Type())
	return m.backend.Status()
}

// Backend detection

func detectBackend(exePath, configPath, stopScriptPath string) (Backend, error) {
	// Try systemd first
	if _, err := exec.LookPath("systemctl"); err == nil {
		if err := exec.Command("systemctl", "is-system-running").Run(); err == nil {
			return NewSystemdBackend(exePath, configPath, stopScriptPath), nil
		}
	}

	// Check for OpenRC
	if _, err := exec.LookPath("rc-service"); err == nil {
		if _, err := os.Stat("/etc/init.d"); err == nil {
			return NewOpenRCBackend(exePath, stopScriptPath), nil
		}
	}

	// Check for SysVinit
	if _, err := os.Stat("/etc/init.d/functions"); err == nil {
		return NewSysVinitBackend(exePath, stopScriptPath), nil
	}

	// Fallback check for init.d directory
	if _, err := os.Stat("/etc/init.d"); err == nil {
		return NewSysVinitBackend(exePath, stopScriptPath), nil
	}

	return nil, errors.NewServiceError("", "detection", "could not detect init system")
}

// Utility functions

// executeCommandWithOutput executes a command and returns a helpful error with output if it fails
func executeCommandWithOutput(cmd *exec.Cmd, operation, backend string) error {
	output, err := cmd.CombinedOutput()
	if err != nil {
		// Include the actual command output in the error message
		outputStr := strings.TrimSpace(string(output))
		if outputStr == "" {
			outputStr = err.Error()
		}
		return errors.NewServiceError(backend, operation,
			fmt.Sprintf("command failed: %s", outputStr))
	}
	return nil
}

// executeCommandWithOutputAndResult executes a command and returns both output and error
func executeCommandWithOutputAndResult(cmd *exec.Cmd, operation, backend string) ([]byte, error) {
	output, err := cmd.CombinedOutput()
	if err != nil {
		// Include the actual command output in the error message
		outputStr := strings.TrimSpace(string(output))
		if outputStr == "" {
			outputStr = err.Error()
		}
		return nil, errors.NewServiceError(backend, operation,
			fmt.Sprintf("command failed: %s", outputStr))
	}
	return output, nil
}

func executeTemplate(tmplStr string, data interface{}) (string, error) {
	tmpl, err := template.New("service").Parse(tmplStr)
	if err != nil {
		return "", fmt.Errorf("failed to parse template: %w", err)
	}

	var buf strings.Builder
	if err := tmpl.Execute(&buf, data); err != nil {
		return "", fmt.Errorf("failed to execute template: %w", err)
	}

	return buf.String(), nil
}
