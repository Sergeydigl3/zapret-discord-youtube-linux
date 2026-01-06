# Dockerfile for Zapret Discord YouTube Go Edition
# Multi-stage build for optimized final image

# Build stage
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Set build flags
ENV CGO_ENABLED=0
ENV GOOS=linux
ENV GOARCH=amd64

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN go build -o zapret \
	-ldflags="-s -w -X main.Version=$(git describe --tags --always --dirty) -X main.BuildDate=$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
	./cmd/zapret

# Final stage
FROM alpine:latest

WORKDIR /app

# Install dependencies
RUN apk add --no-cache \
	bash \
	curl \
	git \
	nftables \
	iptables \
	procps \
	ca-certificates

# Copy built binary from builder
COPY --from=builder /app/zapret /usr/local/bin/zapret

# Copy configuration and strategy files
COPY --from=builder /app/configs /app/configs
COPY --from=builder /app/scripts /app/scripts

# Create necessary directories
RUN mkdir -p /app/zapret-latest /app/custom-strategies /app/bin /app/lists

# Copy example configuration
COPY --from=builder /app/configs/conf.yml.example /app/conf.yml.example

# Set permissions
RUN chmod +x /usr/local/bin/zapret

# Create a non-root user
RUN adduser -D zapret
USER zapret

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/zapret"]
CMD ["--help"]

# Expose common ports (these are just documentation, not actual port exposure)
EXPOSE 80 443 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s \
CMD zapret debug processes || exit 1

# Metadata
LABEL maintainer="Sergey Digl <sergeydigl3@gmail.com>"
LABEL description="Zapret Discord YouTube Go Edition - Network filtering system to bypass YouTube throttling"
LABEL version="1.0.0"
LABEL org.opencontainers.image.source="https://github.com/Sergeydigl3/zapret-discord-youtube-go"