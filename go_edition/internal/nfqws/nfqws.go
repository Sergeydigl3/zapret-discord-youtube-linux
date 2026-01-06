// Package nfqws provides management of nfqws processes for the Zapret application.
// It handles process lifecycle, queue management, and monitoring with context support.
package nfqws

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"syscall"

	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/errors"
	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/strategy"
)

// Manager manages nfqws processes
type Manager struct {
	binaryPath string
	processes  []*ProcessInfo
	mu         sync.Mutex
}

// ProcessInfo contains information about a running nfqws process
type ProcessInfo struct {
	Cmd      *exec.Cmd
	QueueNum int
	PID      int
	Args     []string
}

// Status represents the current status of nfqws processes
type Status struct {
	ProcessCount int
	ActiveQueues []int
	Running      bool
}

// NewManager creates a new nfqws process manager
func NewManager(binaryPath string) *Manager {
	return &Manager{
		binaryPath: binaryPath,
		processes:  make([]*ProcessInfo, 0),
	}
}

// StartProcesses starts nfqws processes based on the parsed strategy
func (m *Manager) StartProcesses(ctx context.Context, params []strategy.NFQWSParams) error {
	select {
	case <-ctx.Done():
		return errors.Wrap(ctx.Err(), "context canceled during nfqws process startup")
	default:
	}

	slog.Debug("Starting nfqws processes", "binary", m.binaryPath, "queues", len(params))

	// Clean up any existing processes first
	if err := m.Cleanup(ctx); err != nil {
		slog.Warn("Failed to cleanup existing nfqws processes", "error", err)
	}

	// Start processes for each queue
	for _, param := range params {
		if err := m.startProcess(ctx, param); err != nil {
			return errors.Wrapf(err, "failed to start process for queue %d", param.QueueNum)
		}
	}

	return nil
}

func (m *Manager) startProcess(ctx context.Context, param strategy.NFQWSParams) error {
	// Build command arguments
	args := []string{"--qnum", strconv.Itoa(param.QueueNum)}
	args = append(args, param.Args...)

	// Create command
	cmd := exec.CommandContext(ctx, m.binaryPath, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Setpgid: true, // Create process group for easier cleanup
	}

	slog.Debug("Starting nfqws process", "binary", m.binaryPath, "queue", param.QueueNum, "args", fmt.Sprintf("%v", args))

	// Start the process
	if err := cmd.Start(); err != nil {
		return errors.NewProcessError(m.binaryPath, 0,
			fmt.Sprintf("failed to start process: %v", err))
	}

	// Store process information
	m.mu.Lock()
	m.processes = append(m.processes, &ProcessInfo{
		Cmd:      cmd,
		QueueNum: param.QueueNum,
		PID:      cmd.Process.Pid,
		Args:     args,
	})
	m.mu.Unlock()

	slog.Info("Started nfqws process", "queue", param.QueueNum, "pid", cmd.Process.Pid)

	return nil
}

// Cleanup stops all nfqws processes managed by this manager
func (m *Manager) Cleanup(ctx context.Context) error {
	select {
	case <-ctx.Done():
		return errors.Wrap(ctx.Err(), "context canceled during nfqws cleanup")
	default:
	}

	slog.Debug("Cleaning up nfqws processes")

	m.mu.Lock()
	defer m.mu.Unlock()

	// Stop all processes
	for _, proc := range m.processes {
		if err := m.stopProcess(ctx, proc); err != nil {
			slog.Warn("Failed to stop nfqws process", "error", err, "pid", proc.PID)
		}
	}

	// Clear the processes list
	m.processes = m.processes[:0]

	return nil
}

func (m *Manager) stopProcess(ctx context.Context, proc *ProcessInfo) error {
	if proc.Cmd == nil || proc.Cmd.Process == nil {
		return nil
	}

	slog.Debug("Stopping nfqws process", "pid", proc.PID)

	// Try graceful termination first
	if err := proc.Cmd.Process.Signal(syscall.SIGTERM); err != nil {
		slog.Warn("Failed to send SIGTERM, trying SIGKILL", "error", err, "pid", proc.PID)
		// Force kill if graceful termination fails
		if err := proc.Cmd.Process.Kill(); err != nil {
			return errors.NewProcessError(m.binaryPath, proc.PID,
				fmt.Sprintf("failed to kill process: %v", err))
		}
	}

	// Wait for process to exit
	_, err := proc.Cmd.Process.Wait()
	if err != nil && err.Error() != "wait: no child processes" {
		return errors.NewProcessError(m.binaryPath, proc.PID,
			fmt.Sprintf("failed to wait for process: %v", err))
	}

	slog.Info("Stopped nfqws process", "pid", proc.PID)
	return nil
}

// Status returns the current status of nfqws processes
func (m *Manager) Status(ctx context.Context) (Status, error) {
	select {
	case <-ctx.Done():
		return Status{}, errors.Wrap(ctx.Err(), "context canceled during nfqws status check")
	default:
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	status := Status{
		ProcessCount: len(m.processes),
		ActiveQueues: make([]int, 0, len(m.processes)),
		Running:      false,
	}

	// Check which processes are still running
	for _, proc := range m.processes {
		if proc.Cmd != nil && proc.Cmd.Process != nil {
			if err := proc.Cmd.Process.Signal(syscall.Signal(0)); err == nil {
				// Process is running
				status.ActiveQueues = append(status.ActiveQueues, proc.QueueNum)
				status.Running = true
			}
		}
	}

	return status, nil
}

// KillAllProcesses kills all nfqws processes on the system (not just managed ones)
func (m *Manager) KillAllProcesses(ctx context.Context) error {
	select {
	case <-ctx.Done():
		return errors.Wrap(ctx.Err(), "context canceled during kill all nfqws processes")
	default:
	}

	slog.Debug("Killing all nfqws processes on system")

	// Use pgrep to find all nfqws processes
	cmd := exec.CommandContext(ctx, "pgrep", "-f", m.binaryPath)
	output, err := cmd.Output()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() == 1 {
			// No processes found, that's ok
			return nil
		}
		return errors.NewProcessError(m.binaryPath, 0,
			fmt.Sprintf("failed to find nfqws processes: %v", err))
	}

	// Parse PIDs and kill them
	pids := strings.Fields(string(output))
	for _, pidStr := range pids {
		pid, err := strconv.Atoi(pidStr)
		if err != nil {
			slog.Warn("Invalid PID format", "error", err, "pid", pidStr)
			continue
		}

		process, err := os.FindProcess(pid)
		if err != nil {
			slog.Warn("Failed to find process", "error", err, "pid", pid)
			continue
		}

		if err := process.Signal(syscall.SIGTERM); err != nil {
			slog.Warn("Failed to terminate process", "error", err, "pid", pid)
		}
	}

	return nil
}

// GetProcessCount returns the number of managed processes
func (m *Manager) GetProcessCount() int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return len(m.processes)
}

// GetActiveQueues returns the queue numbers of active processes
func (m *Manager) GetActiveQueues() []int {
	m.mu.Lock()
	defer m.mu.Unlock()

	queues := make([]int, 0, len(m.processes))
	for _, proc := range m.processes {
		queues = append(queues, proc.QueueNum)
	}
	return queues
}
