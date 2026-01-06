// Package service provides OpenRC backend implementation
package service

import (
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/errors"
)

// OpenRCBackend implements the Backend interface for OpenRC
type OpenRCBackend struct {
	exePath        string
	stopScriptPath string
}

// NewOpenRCBackend creates a new OpenRC backend
func NewOpenRCBackend(exePath, stopScriptPath string) *OpenRCBackend {
	return &OpenRCBackend{
		exePath:        exePath,
		stopScriptPath: stopScriptPath,
	}
}

// Type returns the backend type
func (b *OpenRCBackend) Type() string {
	return OpenRCType
}

// Install installs the OpenRC service
func (b *OpenRCBackend) Install() error {
	slog.Debug("Installing OpenRC service")

	// Generate service file
	serviceContent, err := b.generateServiceFile()
	if err != nil {
		return errors.Wrap(err, "failed to generate OpenRC service file")
	}

	servicePath := fmt.Sprintf("/etc/init.d/%s", ServiceName)
	if err := os.WriteFile(servicePath, []byte(serviceContent), 0755); err != nil {
		return errors.NewServiceError(OpenRCType, "install",
			fmt.Sprintf("failed to write service file: %v", err))
	}

	// Add to default runlevel
	if err := executeCommandWithOutput(exec.Command("rc-update", "add", ServiceName, "default"), "install", OpenRCType); err != nil {
		return err
	}

	// Start service
	if err := executeCommandWithOutput(exec.Command("rc-service", ServiceName, "start"), "install", OpenRCType); err != nil {
		return err
	}

	slog.Info("OpenRC service installed and started successfully")
	return nil
}

// Remove removes the OpenRC service
func (b *OpenRCBackend) Remove() error {
	slog.Debug("Removing OpenRC service")

	// Stop service
	if err := executeCommandWithOutput(exec.Command("rc-service", ServiceName, "stop"), "remove", OpenRCType); err != nil {
		slog.Warn("Failed to stop service", "error", err)
	}

	// Remove from runlevel
	if err := executeCommandWithOutput(exec.Command("rc-update", "del", ServiceName, "default"), "remove", OpenRCType); err != nil {
		slog.Warn("Failed to remove from runlevel", "error", err)
	}

	// Remove service file
	servicePath := fmt.Sprintf("/etc/init.d/%s", ServiceName)
	if err := os.Remove(servicePath); err != nil && !os.IsNotExist(err) {
		return errors.NewServiceError(OpenRCType, "remove",
			fmt.Sprintf("failed to remove service file: %v", err))
	}

	slog.Info("OpenRC service removed successfully")
	return nil
}

// Start starts the OpenRC service
func (b *OpenRCBackend) Start() error {
	slog.Debug("Starting OpenRC service")

	if err := executeCommandWithOutput(exec.Command("rc-service", ServiceName, "start"), "start", OpenRCType); err != nil {
		return err
	}

	slog.Info("OpenRC service started successfully")
	return nil
}

// Stop stops the OpenRC service
func (b *OpenRCBackend) Stop() error {
	slog.Debug("Stopping OpenRC service")

	if err := executeCommandWithOutput(exec.Command("rc-service", ServiceName, "stop"), "stop", OpenRCType); err != nil {
		return err
	}

	slog.Info("OpenRC service stopped successfully")
	return nil
}

// Status returns the OpenRC service status
func (b *OpenRCBackend) Status() error {
	slog.Debug("Checking OpenRC service status")

	cmd := exec.Command("rc-service", ServiceName, "status")
	output, err := executeCommandWithOutputAndResult(cmd, "status", OpenRCType)
	if err != nil {
		return err
	}

	fmt.Println(string(output))
	return nil
}

// generateServiceFile generates the OpenRC service file content
func (b *OpenRCBackend) generateServiceFile() (string, error) {
	tmpl := `#!/sbin/openrc-run

description="Zapret Discord YouTube Service"
command="{{.ExecPath}}"
command_args="-nointeractive"
command_background=false
pidfile="/run/{{.ServiceName}}.pid"

depend() {
	need net
	after firewall
}

start_pre() {
	checkpath --directory --owner root:root --mode 0755 /run/{{.ServiceName}}
}

stop() {
	ebegin "Stopping {{.ServiceName}}"
	{{.StopScriptPath}}
	eend $?
}
`

	data := struct {
		ServiceName    string
		ExecPath       string
		StopScriptPath string
	}{
		ServiceName:    ServiceName,
		ExecPath:       b.exePath,
		StopScriptPath: b.stopScriptPath,
	}

	return executeTemplate(tmpl, data)
}
