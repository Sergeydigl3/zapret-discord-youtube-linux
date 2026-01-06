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

# Install the application
install:
	@echo "Installing Zapret Discord YouTube..."
	@sudo cp bin/$(BINARY_NAME) /usr/local/bin/$(BINARY_NAME)
	@sudo chmod +x /usr/local/bin/$(BINARY_NAME)
	@echo "Installation complete"

# Install as service
install-service:
	@echo "Installing as service..."
	@sudo ./bin/$(BINARY_NAME) service install

# Uninstall service
uninstall-service:
	@echo "Uninstalling service..."
	@sudo ./bin/$(BINARY_NAME) service remove

# Start service
start-service:
	@echo "Starting service..."
	@sudo ./bin/$(BINARY_NAME) service start

# Stop service
stop-service:
	@echo "Stopping service..."
	@sudo ./bin/$(BINARY_NAME) service stop

# Check service status
service-status:
	@echo "Checking service status..."
	@sudo ./bin/$(BINARY_NAME) service status

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
	@echo "  build-linux        - Build for Linux"
	@echo "  build-windows      - Build for Windows"
	@echo "  build-mac          - Build for macOS"
	@echo "  build-all          - Build for all platforms"
	@echo "  run                - Run the application"
	@echo "  run-debug          - Run with debug logging"
	@echo "  install            - Install the application"
	@echo "  install-service    - Install as service"
	@echo "  uninstall-service  - Uninstall service"
	@echo "  start-service      - Start service"
	@echo "  stop-service       - Stop service"
	@echo "  service-status     - Check service status"
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

.PHONY: all build build-linux build-windows build-mac build-all run run-debug install install-service uninstall-service start-service stop-service service-status clean test test-race test-coverage fmt lint docs docker-build docker-run docker-push docker-release deps help dev profile vuln-check