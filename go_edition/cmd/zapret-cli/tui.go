package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/gdamore/tcell/v2"
	"github.com/rivo/tview"

	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/twirp"
	"github.com/sergeydigl3/zapret-discord-youtube-go/internal/zapret-daemon"
)

// TUIApp represents the TUI application
type TUIApp struct {
	app           *tview.Application
	pages         *tview.Pages
	menu          *tview.List
	statusView    *tview.TextView
	processesView *tview.TextView
	firewallView  *tview.TextView
	configView    *tview.TextView
	client        twirp.ZapretServiceClient
}

// NewTUIApp creates a new TUI application
func NewTUIApp(client twirp.ZapretServiceClient) *TUIApp {
	app := tview.NewApplication()
	pages := tview.NewPages()

	// Create main menu
	menu := tview.NewList()
	menu.SetTitle("Zapret TUI - Main Menu").SetBorder(true)
	menu.AddItem("Status", "Check daemon status", 's', func() {
		showStatusPage(pages, client)
	})
	menu.AddItem("Start", "Start the application", 't', func() {
		startApplication(client)
	})
	menu.AddItem("Stop", "Stop the application", 'p', func() {
		stopApplication(client)
	})
	menu.AddItem("Restart", "Restart the application", 'r', func() {
		restartApplication(client)
	})
	menu.AddItem("Processes", "View active processes", 'c', func() {
		showProcessesPage(pages, client)
	})
	menu.AddItem("Firewall", "View firewall rules", 'f', func() {
		showFirewallPage(pages, client)
	})
	menu.AddItem("Configuration", "View configuration", 'g', func() {
		showConfigPage(pages, client)
	})
	menu.AddItem("Quit", "Exit the application", 'q', func() {
		app.Stop()
	})

	// Create status view
	statusView := tview.NewTextView()
	statusView.SetTitle("Status").SetBorder(true)

	// Create processes view
	processesView := tview.NewTextView()
	processesView.SetTitle("Active Processes").SetBorder(true)

	// Create firewall view
	firewallView := tview.NewTextView()
	firewallView.SetTitle("Firewall Rules").SetBorder(true)

	// Create config view
	configView := tview.NewTextView()
	configView.SetTitle("Configuration").SetBorder(true)

	// Add pages
	pages.AddPage("menu", menu, true, true)
	pages.AddPage("status", statusView, true, false)
	pages.AddPage("processes", processesView, true, false)
	pages.AddPage("firewall", firewallView, true, false)
	pages.AddPage("config", configView, true, false)

	return &TUIApp{
		app:           app,
		pages:         pages,
		menu:          menu,
		statusView:    statusView,
		processesView: processesView,
		firewallView:  firewallView,
		configView:    configView,
		client:        client,
	}
}

// Run starts the TUI application
func (t *TUIApp) Run() error {
	// Set up key bindings
	t.app.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
		if event.Key() == tcell.KeyEsc {
			t.pages.SwitchToPage("menu")
			return nil
		}
		return event
	})

	// Start auto-refresh for status
	go t.autoRefreshStatus()

	if err := t.app.SetRoot(t.pages, true).Run(); err != nil {
		return fmt.Errorf("failed to run TUI: %w", err)
	}

	return nil
}

// autoRefreshStatus periodically updates the status
func (t *TUIApp) autoRefreshStatus() {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			t.updateStatus()
		}
	}
}

// updateStatus updates the status display
func (t *TUIApp) updateStatus() {
	resp, err := t.client.GetActiveProcesses(context.Background(), &zapretdaemon.GetActiveProcessesRequest{})
	if err != nil {
		t.statusView.SetText(fmt.Sprintf("Error getting status: %v", err))
		return
	}

	statusText := fmt.Sprintf("Daemon Status: Running\nActive Processes: %d\n", len(resp.Processes))
	for i, process := range resp.Processes {
		statusText += fmt.Sprintf("  %d. %s\n", i+1, process)
	}
	t.statusView.SetText(statusText)
}

// showStatusPage displays the status page
func showStatusPage(pages *tview.Pages, client twirp.ZapretServiceClient) {
	pages.SwitchToPage("status")
}

// startApplication starts the application
func startApplication(client twirp.ZapretServiceClient) {
	resp, err := client.RunSelectedStrategy(context.Background(), &zapretdaemon.RunSelectedStrategyRequest{
		StrategyPath: "default.bat",
	})
	if err != nil {
		showErrorMessage(fmt.Sprintf("Failed to start application: %v", err))
		return
	}
	showInfoMessage(fmt.Sprintf("Application started successfully: %s", resp.Message))
}

// stopApplication stops the application
func stopApplication(client twirp.ZapretServiceClient) {
	resp, err := client.StopStrategy(context.Background(), &zapretdaemon.StopStrategyRequest{})
	if err != nil {
		showErrorMessage(fmt.Sprintf("Failed to stop application: %v", err))
		return
	}
	showInfoMessage(fmt.Sprintf("Application stopped successfully: %s", resp.Message))
}

// restartApplication restarts the application
func restartApplication(client twirp.ZapretServiceClient) {
	resp, err := client.RestartDaemon(context.Background(), &zapretdaemon.RestartDaemonRequest{})
	if err != nil {
		showErrorMessage(fmt.Sprintf("Failed to restart daemon: %v", err))
		return
	}
	showInfoMessage(fmt.Sprintf("Daemon restarted successfully: %s", resp.Message))
}

// showProcessesPage displays the processes page
func showProcessesPage(pages *tview.Pages, client twirp.ZapretServiceClient) {
	resp, err := client.GetActiveProcesses(context.Background(), &zapretdaemon.GetActiveProcessesRequest{})
	if err != nil {
		if processesView, ok := pages.Get("processes").(*tview.TextView); ok {
			processesView.SetText(fmt.Sprintf("Error getting processes: %v", err))
		}
		return
	}

	processesText := fmt.Sprintf("Active Processes: %d\n", len(resp.Processes))
	for i, process := range resp.Processes {
		processesText += fmt.Sprintf("  %d. %s\n", i+1, process)
	}

	if processesView, ok := pages.Get("processes").(*tview.TextView); ok {
		processesView.SetText(processesText)
	}
	pages.SwitchToPage("processes")
}

// showFirewallPage displays the firewall page
func showFirewallPage(pages *tview.Pages, client twirp.ZapretServiceClient) {
	resp, err := client.GetActiveNFTRules(context.Background(), &zapretdaemon.GetActiveNFTRulesRequest{})
	if err != nil {
		if firewallView, ok := pages.Get("firewall").(*tview.TextView); ok {
			firewallView.SetText(fmt.Sprintf("Error getting firewall rules: %v", err))
		}
		return
	}

	firewallText := fmt.Sprintf("Firewall Status: Active\nActive NFT Rules: %d\n", len(resp.Rules))
	for i, rule := range resp.Rules {
		firewallText += fmt.Sprintf("  %d. %s\n", i+1, rule)
	}

	if firewallView, ok := pages.Get("firewall").(*tview.TextView); ok {
		firewallView.SetText(firewallText)
	}
	pages.SwitchToPage("firewall")
}

// showConfigPage displays the configuration page
func showConfigPage(pages *tview.Pages, client twirp.ZapretServiceClient) {
	// Get available versions
	versionsResp, err := client.GetAvailableVersions(context.Background(), &zapretdaemon.GetAvailableVersionsRequest{})
	if err != nil {
		if configView, ok := pages.Get("config").(*tview.TextView); ok {
			configView.SetText(fmt.Sprintf("Error getting configuration: %v", err))
		}
		return
	}

	// Get active NFT rules
	rulesResp, err := client.GetActiveNFTRules(context.Background(), &zapretdaemon.GetActiveNFTRulesRequest{})
	if err != nil {
		if configView, ok := pages.Get("config").(*tview.TextView); ok {
			configView.SetText(fmt.Sprintf("Error getting NFT rules: %v", err))
		}
		return
	}

	configText := "Available Versions:\n"
	for i, version := range versionsResp.Versions {
		configText += fmt.Sprintf("  %d. %s\n", i+1, version)
	}

	configText += "\nActive NFT Rules:\n"
	for i, rule := range rulesResp.Rules {
		configText += fmt.Sprintf("  %d. %s\n", i+1, rule)
	}

	if configView, ok := pages.Get("config").(*tview.TextView); ok {
		configView.SetText(configText)
	}
	pages.SwitchToPage("config")
}

// showInfoMessage shows an information message
func showInfoMessage(message string) {
	modal := tview.NewModal()
	modal.SetText(message)
	modal.AddButtons([]string{"OK"})
	modal.SetDoneFunc(func(buttonIndex int, buttonLabel string) {
		if buttonLabel == "OK" {
			pages.SwitchToPage("menu")
		}
	})
	pages.AddPage("modal", modal, true, true)
}

// showErrorMessage shows an error message
func showErrorMessage(message string) {
	modal := tview.NewModal()
	modal.SetText(message)
	modal.SetBackgroundColor(tcell.ColorRed)
	modal.AddButtons([]string{"OK"})
	modal.SetDoneFunc(func(buttonIndex int, buttonLabel string) {
		if buttonLabel == "OK" {
			pages.SwitchToPage("menu")
		}
	})
	pages.AddPage("modal", modal, true, true)
}