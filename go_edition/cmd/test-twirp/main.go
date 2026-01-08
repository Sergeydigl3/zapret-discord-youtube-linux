// Package main provides a simple test for the Twirp service
package main

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/sergeydigl3/zapret-discord-youtube-go/rpc/zapret-daemon"
)

func main() {
	fmt.Println("Testing Twirp service...")

	// Create a Twirp client
	client := twirp.NewClient("http://localhost:8080/twirp")

	// Test GetStrategyList
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	fmt.Println("Calling GetStrategyList...")
	resp, err := client.GetStrategyList(ctx)
	if err != nil {
		log.Fatalf("Failed to call GetStrategyList: %v", err)
	}

	fmt.Printf("Strategy list received: %d strategies\n", len(resp.StrategyPaths))
	for i, path := range resp.StrategyPaths {
		fmt.Printf("  %d: %s\n", i+1, path)
	}

	// Test GetAvailableVersions
	fmt.Println("\nCalling GetAvailableVersions...")
	versionsResp, err := client.GetAvailableVersions(ctx)
	if err != nil {
		log.Fatalf("Failed to call GetAvailableVersions: %v", err)
	}

	fmt.Printf("Available versions: %v\n", versionsResp.Versions)

	// Test GetActiveNFTRules
	fmt.Println("\nCalling GetActiveNFTRules...")
	rulesResp, err := client.GetActiveNFTRules(ctx)
	if err != nil {
		log.Fatalf("Failed to call GetActiveNFTRules: %v", err)
	}

	fmt.Printf("Active NFT rules: %v\n", rulesResp.Rules)

	// Test GetActiveProcesses
	fmt.Println("\nCalling GetActiveProcesses...")
	processesResp, err := client.GetActiveProcesses(ctx)
	if err != nil {
		log.Fatalf("Failed to call GetActiveProcesses: %v", err)
	}

	fmt.Printf("Active processes: %v\n", processesResp.Processes)

	fmt.Println("\nAll Twirp service tests completed successfully!")
}