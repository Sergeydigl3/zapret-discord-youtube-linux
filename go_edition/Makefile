# Makefile for Zapret Discord YouTube Go Edition
# Provides common development and deployment tasks

# Configuration
BINARY_NAME := zapret
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
BUILD_DATE := $(shell date -u +'%Y-%m-%dT%H:%M:%SZ')
GO_VERSION := 1.21

# Default target
all: build

# Build the application
build:
	@echo "Building Zapret Discord YouTube Go Edition..."
	@go build -o bin/$(BINARY_NAME) \
		-ldflags="-s -w -X main.Version=$(VERSION) -X main.BuildDate=$(BUILD_DATE)" \
		./cmd/zapret
	@echo "Build complete: bin/$(BINARY_NAME)"

# Build the daemon
build-daemon:
	@echo "Building Zapret daemon..."
	@go build -o bin/zapret-daemon \
		-ldflags="-s -w -X main.Version=$(VERSION) -X main.BuildDate=$(BUILD_DATE)" \
		./cmd/zapret-daemon
	@echo "Build complete: bin/zapret-daemon"

# Build the CLI
build-cli:
	@echo "Building Zapret CLI..."
	@go build -o bin/zapret-cli \
		-ldflags="-s -w -X main.Version=$(VERSION) -X main.BuildDate=$(BUILD_DATE)" \
		./cmd/zapret-cli
	@echo "Build complete: bin/zapret-cli"

# Build all components
build-all:
	@$(MAKE) build
	@$(MAKE) build-daemon
	@$(MAKE) build-cli

# Build for specific platform
build-linux:
	@echo "Building for Linux..."
	@GOOS=linux GOARCH=amd64 go build -o bin/$(BINARY_NAME)-linux-amd64 \
		-ldflags="-s -w -X main.Version=$(VERSION) -X main.BuildDate=$(BUILD_DATE)" \
		./cmd/zapret

build-windows:
	@echo "Building for Windows..."
	@GOOS=windows GOARCH=amd64 go build -o bin/$(BINARY_NAME)-windows-amd64.exe \
		-ldflags="-s -w -X main.Version=$(VERSION) -X main.BuildDate=$(BUILD_DATE)" \
		./cmd/zapret

build-mac:
	@echo "Building for macOS..."
	@GOOS=darwin GOARCH=amd64 go build -o bin/$(BINARY_NAME)-macos-amd64 \
		-ldflags="-s -w -X main.Version=$(VERSION) -X main.BuildDate=$(BUILD_DATE)" \
		./cmd/zapret

# Cross-compile for all platforms
build-all:
	@mkdir -p bin
	@$(MAKE) build-linux
	@$(MAKE) build-windows
	@$(MAKE) build-mac
	@echo "All builds complete"

# Run the application
run:
	@echo "Running Zapret Discord YouTube..."
	@./bin/$(BINARY_NAME)

# Run with debug logging
run-debug:
	@echo "Running with debug logging..."
	@ZAPRET_LOG_LEVEL=debug ./bin/$(BINARY_NAME)

# Run the daemon
run-daemon:
	@echo "Running Zapret daemon..."
	@./bin/zapret-daemon

# Run the daemon in background
run-daemon-bg:
	@echo "Running Zapret daemon in background..."
	@nohup ./bin/zapret-daemon > /dev/null 2>&1 &
	@echo $! > /tmp/zapret-daemon.pid
	@echo "Daemon started with PID: $$(cat /tmp/zapret-daemon.pid)"

# Stop the daemon
stop-daemon:
	@echo "Stopping Zapret daemon..."
	@if [ -f /tmp/zapret-daemon.pid ]; then \
		kill $$(cat /tmp/zapret-daemon.pid) && rm /tmp/zapret-daemon.pid; \
		else \
		./bin/zapret-cli stop; \
		fi

# Install the application
install:
	@echo "Installing Zapret Discord YouTube..."
	@sudo cp bin/$(BINARY_NAME) /usr/local/bin/$(BINARY_NAME)
	@sudo chmod +x /usr/local/bin/$(BINARY_NAME)
	@echo "Installation complete"

# Install daemon and CLI
install-daemon:
	@echo "Installing Zapret daemon and CLI..."
	@sudo cp bin/zapret-daemon /usr/local/bin/zapret-daemon
	@sudo cp bin/zapret-cli /usr/local/bin/zapret-cli
	@sudo chmod +x /usr/local/bin/zapret-daemon /usr/local/bin/zapret-cli
	@sudo mkdir -p /etc/zapret /var/log/zapret
	@sudo cp configs/conf.daemon.yml.example /etc/zapret/conf.yml
	@echo "Installation complete"

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf bin/
	@echo "Clean complete"

# Run tests
test:
	@echo "Running tests..."
	@go test -v ./...

# Run tests with race detector
test-race:
	@echo "Running tests with race detector..."
	@go test -race -v ./...

# Run tests with coverage
test-coverage:
	@echo "Running tests with coverage..."
	@go test -coverprofile=coverage.out -v ./...
	@go tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report generated: coverage.html"

# Format code
fmt:
	@echo "Formatting code..."
	@gofmt -s -w .
	@echo "Code formatting complete"

# Lint code
lint:
	@echo "Linting code..."
	@go vet ./...
	@golangci-lint run
	@echo "Linting complete"

# Generate documentation
docs:
	@echo "Generating documentation..."
	@go doc -all ./... > docs/godoc.txt
	@echo "Documentation generated: docs/godoc.txt"

# Build Docker image
docker-build:
	@echo "Building Docker image..."
	@docker build -t zapret-discord-youtube-go:latest .
	@echo "Docker image built"

# Run Docker container
docker-run:
	@echo "Running Docker container..."
	@docker run -it --rm --name zapret \
		--cap-add=NET_ADMIN \
		--cap-add=NET_RAW \
		-v $(PWD)/configs:/app/configs \
		-v $(PWD)/zapret-latest:/app/zapret-latest \
		zapret-discord-youtube-go:latest

# Push Docker image
docker-push:
	@echo "Pushing Docker image..."
	@docker push zapret-discord-youtube-go:latest
	@echo "Docker image pushed"

# Create release
docker-release:
	@echo "Creating release..."
	@docker buildx build --platform linux/amd64,linux/arm64 \
		-t zapret-discord-youtube-go:latest \
		-t zapret-discord-youtube-go:$(VERSION) \
		--push .
	@echo "Release created and pushed"

# Generate protobuf code
gen:
	@echo "Generating protobuf code..."
	@protoc --proto_path=. --twirp_out=. --go_out=. rpc/zapret-daemon/service.proto
	@echo "Protobuf code generated"

# Update dependencies
deps:
	@echo "Updating dependencies..."
	@go mod tidy
	@go get -u ./...
	@echo "Dependencies updated"

# Show help
help:
	@echo "Makefile for Zapret Discord YouTube Go Edition"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  build              - Build the application"
	@echo "  build-daemon       - Build the daemon"
	@echo "  build-cli          - Build the CLI"
	@echo "  build-all          - Build all components"
	@echo "  build-linux        - Build for Linux"
	@echo "  build-windows      - Build for Windows"
	@echo "  build-mac          - Build for macOS"
	@echo "  run                - Run the application"
	@echo "  run-debug          - Run with debug logging"
	@echo "  run-daemon         - Run the daemon"
	@echo "  run-daemon-bg      - Run daemon in background"
	@echo "  stop-daemon        - Stop the daemon"
	@echo "  install            - Install the application"
	@echo "  install-daemon     - Install daemon and CLI"
	@echo "  clean              - Clean build artifacts"
	@echo "  test               - Run tests"
	@echo "  test-race          - Run tests with race detector"
	@echo "  test-coverage      - Run tests with coverage"
	@echo "  fmt                - Format code"
	@echo "  lint               - Lint code"
	@echo "  docs               - Generate documentation"
	@echo "  docker-build       - Build Docker image"
	@echo "  docker-run         - Run Docker container"
	@echo "  docker-push        - Push Docker image"
	@echo "  docker-release     - Create and push release"
	@echo "  deps               - Update dependencies"
	@echo "  help               - Show this help"

# Development target
dev:
	@echo "Starting development mode..."
	@go run -race cmd/zapret/main.go

# Profile the application
profile:
	@echo "Profiling application..."
	@go tool pprof -http=:8080 http://localhost:6060/debug/pprof/profile

# Check for vulnerabilities
vuln-check:
	@echo "Checking for vulnerabilities..."
	@govulncheck ./...

.PHONY: all build build-linux build-windows build-mac build-all run run-debug install install-service uninstall-service start-service stop-service service-status clean gen test test-race test-coverage fmt lint docs docker-build docker-run docker-push docker-release deps help dev profile vuln-check