// Package service provides systemd backend implementation
package service

import (
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/errors"
)

// SystemdBackend implements the Backend interface for systemd
type SystemdBackend struct {
	exePath        string
	configPath     string
	stopScriptPath string
}

// NewSystemdBackend creates a new systemd backend
func NewSystemdBackend(exePath, configPath, stopScriptPath string) *SystemdBackend {
	return &SystemdBackend{
		exePath:        exePath,
		configPath:     configPath,
		stopScriptPath: stopScriptPath,
	}
}

// Type returns the backend type
func (b *SystemdBackend) Type() string {
	return SystemdType
}

// Install installs the systemd service
func (b *SystemdBackend) Install() error {
	slog.Debug("Installing systemd service")

	// Create service file
	serviceContent, err := b.generateServiceFile()
	if err != nil {
		return errors.Wrap(err, "failed to generate systemd service file")
	}

	servicePath := fmt.Sprintf("/etc/systemd/system/%s.service", ServiceName)
	if err := os.WriteFile(servicePath, []byte(serviceContent), 0644); err != nil {
		return errors.NewServiceError(SystemdType, "install",
			fmt.Sprintf("failed to write service file: %v", err))
	}

	// Reload systemd
	if err := executeCommandWithOutput(exec.Command("systemctl", "daemon-reload"), "install", SystemdType); err != nil {
		return err
	}

	// Enable service
	if err := executeCommandWithOutput(exec.Command("systemctl", "enable", ServiceName), "install", SystemdType); err != nil {
		return err
	}

	// Start service
	if err := executeCommandWithOutput(exec.Command("systemctl", "start", ServiceName), "install", SystemdType); err != nil {
		return err
	}

	slog.Info("Systemd service installed and started successfully")
	return nil
}

// Remove removes the systemd service
func (b *SystemdBackend) Remove() error {
	slog.Debug("Removing systemd service")

	// Stop service
	if err := executeCommandWithOutput(exec.Command("systemctl", "stop", ServiceName), "remove", SystemdType); err != nil {
		slog.Warn("Failed to stop service", "error", err)
	}

	// Disable service
	if err := executeCommandWithOutput(exec.Command("systemctl", "disable", ServiceName), "remove", SystemdType); err != nil {
		slog.Warn("Failed to disable service", "error", err)
	}

	// Remove service file
	servicePath := fmt.Sprintf("/etc/systemd/system/%s.service", ServiceName)
	if err := os.Remove(servicePath); err != nil && !os.IsNotExist(err) {
		return errors.NewServiceError(SystemdType, "remove",
			fmt.Sprintf("failed to remove service file: %v", err))
	}

	// Reload systemd
	if err := executeCommandWithOutput(exec.Command("systemctl", "daemon-reload"), "remove", SystemdType); err != nil {
		return err
	}

	slog.Info("Systemd service removed successfully")
	return nil
}

// Start starts the systemd service
func (b *SystemdBackend) Start() error {
	slog.Debug("Starting systemd service")

	if err := executeCommandWithOutput(exec.Command("systemctl", "start", ServiceName), "start", SystemdType); err != nil {
		return err
	}

	slog.Info("Systemd service started successfully")
	return nil
}

// Stop stops the systemd service
func (b *SystemdBackend) Stop() error {
	slog.Debug("Stopping systemd service")

	if err := executeCommandWithOutput(exec.Command("systemctl", "stop", ServiceName), "stop", SystemdType); err != nil {
		return err
	}

	slog.Info("Systemd service stopped successfully")
	return nil
}

// Status returns the systemd service status
func (b *SystemdBackend) Status() error {
	slog.Debug("Checking systemd service status")

	cmd := exec.Command("systemctl", "status", ServiceName)
	output, err := executeCommandWithOutputAndResult(cmd, "status", SystemdType)
	if err != nil {
		return err
	}

	fmt.Println(string(output))
	return nil
}

// generateServiceFile generates the systemd service file content
func (b *SystemdBackend) generateServiceFile() (string, error) {
	tmpl := `[Unit]
Description=Zapret Discord YouTube Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory={{.WorkingDir}}
User=root
ExecStart={{.ExecPath}} -nointeractive
ExecStop={{.StopScriptPath}}
ExecStopPost=/usr/bin/env echo "Service stopped"
PIDFile=/run/{{.ServiceName}}.pid
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
`

	data := struct {
		ServiceName    string
		ExecPath       string
		StopScriptPath string
		WorkingDir     string
	}{
		ServiceName:    ServiceName,
		ExecPath:       b.exePath,
		StopScriptPath: b.stopScriptPath,
		WorkingDir:     filepath.Dir(b.exePath),
	}

	return executeTemplate(tmpl, data)
}
