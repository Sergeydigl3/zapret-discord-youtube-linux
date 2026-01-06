// Package service provides SysVinit backend implementation
package service

import (
	"fmt"
	"log/slog"
	"os"
	"os/exec"

	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/errors"
)

// SysVinitBackend implements the Backend interface for SysVinit
type SysVinitBackend struct {
	exePath        string
	stopScriptPath string
}

// NewSysVinitBackend creates a new SysVinit backend
func NewSysVinitBackend(exePath, stopScriptPath string) *SysVinitBackend {
	return &SysVinitBackend{
		exePath:        exePath,
		stopScriptPath: stopScriptPath,
	}
}

// Type returns the backend type
func (b *SysVinitBackend) Type() string {
	return SysVinitType
}

// Install installs the SysVinit service
func (b *SysVinitBackend) Install() error {
	slog.Debug("Installing SysVinit service")

	// Generate service file
	serviceContent, err := b.generateServiceFile()
	if err != nil {
		return errors.Wrap(err, "failed to generate SysVinit service file")
	}

	servicePath := fmt.Sprintf("/etc/init.d/%s", ServiceName)
	if err := os.WriteFile(servicePath, []byte(serviceContent), 0755); err != nil {
		return errors.NewServiceError(SysVinitType, "install",
			fmt.Sprintf("failed to write service file: %v", err))
	}

	// Add to startup
	if err := b.addToStartup(); err != nil {
		slog.Warn("Failed to add to startup", "error", err)
	}

	// Start service
	if err := executeCommandWithOutput(exec.Command(servicePath, "start"), "install", SysVinitType); err != nil {
		return err
	}

	slog.Info("SysVinit service installed and started successfully")
	return nil
}

// Remove removes the SysVinit service
func (b *SysVinitBackend) Remove() error {
	slog.Debug("Removing SysVinit service")

	// Stop service
	servicePath := fmt.Sprintf("/etc/init.d/%s", ServiceName)
	if err := executeCommandWithOutput(exec.Command(servicePath, "stop"), "remove", SysVinitType); err != nil {
		slog.Warn("Failed to stop service", "error", err)
	}

	// Remove from startup
	if err := b.removeFromStartup(); err != nil {
		slog.Warn("Failed to remove from startup", "error", err)
	}

	// Remove service file
	if err := os.Remove(servicePath); err != nil && !os.IsNotExist(err) {
		return errors.NewServiceError(SysVinitType, "remove",
			fmt.Sprintf("failed to remove service file: %v", err))
	}

	slog.Info("SysVinit service removed successfully")
	return nil
}

// Start starts the SysVinit service
func (b *SysVinitBackend) Start() error {
	slog.Debug("Starting SysVinit service")

	servicePath := fmt.Sprintf("/etc/init.d/%s", ServiceName)
	if err := executeCommandWithOutput(exec.Command(servicePath, "start"), "start", SysVinitType); err != nil {
		return err
	}

	slog.Info("SysVinit service started successfully")
	return nil
}

// Stop stops the SysVinit service
func (b *SysVinitBackend) Stop() error {
	slog.Debug("Stopping SysVinit service")

	servicePath := fmt.Sprintf("/etc/init.d/%s", ServiceName)
	if err := executeCommandWithOutput(exec.Command(servicePath, "stop"), "stop", SysVinitType); err != nil {
		return err
	}

	slog.Info("SysVinit service stopped successfully")
	return nil
}

// Status returns the SysVinit service status
func (b *SysVinitBackend) Status() error {
	slog.Debug("Checking SysVinit service status")

	servicePath := fmt.Sprintf("/etc/init.d/%s", ServiceName)
	cmd := exec.Command(servicePath, "status")
	output, err := executeCommandWithOutputAndResult(cmd, "status", SysVinitType)
	if err != nil {
		return err
	}

	fmt.Println(string(output))
	return nil
}

// generateServiceFile generates the SysVinit service file content
func (b *SysVinitBackend) generateServiceFile() (string, error) {
	tmpl := `#!/bin/sh
### BEGIN INIT INFO
# Provides:          {{.ServiceName}}
# Required-Start:    $network $local_fs
# Required-Stop:     $network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: {{.ServiceName}}
### END INIT INFO

case "$1" in
    start)
        echo "Starting {{.ServiceName}}"
        {{.ExecPath}} -nointeractive
        ;;
    stop)
        echo "Stopping {{.ServiceName}}"
        {{.StopScriptPath}}
        ;;
    restart)
        $0 stop
        sleep 1
        $0 start
        ;;
    status)
        if pgrep -f "{{.ExecPath}}" >/dev/null; then
            echo "{{.ServiceName}} is running"
        else
            echo "{{.ServiceName}} is not running"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
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

// addToStartup adds the service to system startup
func (b *SysVinitBackend) addToStartup() error {
	// Try update-rc.d first
	if _, err := exec.LookPath("update-rc.d"); err == nil {
		if err := executeCommandWithOutput(exec.Command("update-rc.d", ServiceName, "defaults"), "install", SysVinitType); err != nil {
			return err
		}
		return nil
	}

	// Try chkconfig
	if _, err := exec.LookPath("chkconfig"); err == nil {
		if err := executeCommandWithOutput(exec.Command("chkconfig", "--add", ServiceName), "install", SysVinitType); err != nil {
			return err
		}
		return nil
	}

	return nil
}

// removeFromStartup removes the service from system startup
func (b *SysVinitBackend) removeFromStartup() error {
	// Try update-rc.d first
	if _, err := exec.LookPath("update-rc.d"); err == nil {
		if err := executeCommandWithOutput(exec.Command("update-rc.d", "-f", ServiceName, "remove"), "remove", SysVinitType); err != nil {
			return err
		}
		return nil
	}

	// Try chkconfig
	if _, err := exec.LookPath("chkconfig"); err == nil {
		if err := executeCommandWithOutput(exec.Command("chkconfig", "--del", ServiceName), "remove", SysVinitType); err != nil {
			return err
		}
		return nil
	}

	return nil
}
