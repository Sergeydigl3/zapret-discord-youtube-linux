# Zapret Discord YouTube - Go Edition

![Go Version](https://img.shields.io/badge/go-1.21-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Build Status](https://img.shields.io/badge/build-passing-brightgreen.svg)

A high-performance Go implementation of the Zapret Discord YouTube network filtering system to bypass YouTube throttling.

## Features

- **High Performance**: Written in Go for better performance and lower resource usage
- **Modern Practices**: Uses contexts, generics, structured logging, and proper error handling
- **Multi-Platform**: Supports Linux, Windows, and macOS
- **Multiple Firewalls**: Works with both nftables and iptables
- **Service Integration**: Supports systemd, OpenRC, and SysVinit
- **Docker Support**: Ready-to-use Docker container with multi-arch support
- **Comprehensive CLI**: Feature-rich command-line interface
- **Configuration Management**: Environment variables and config file support
- **Self-Installation**: Can install itself as a system service

## Installation

### From Source

```bash
# Clone the repository
git clone https://github.com/Sergeydigl3/zapret-discord-youtube-go.git
cd zapret-discord-youtube-go

# Build the application
make build

# Install the binary
sudo make install
```

### Using Docker

```bash
# Build the Docker image
make docker-build

# Run the container
docker run -it --rm --name zapret \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  -v $(pwd)/configs:/app/configs \
  -v $(pwd)/zapret-latest:/app/zapret-latest \
  zapret-discord-youtube-go:latest
```

### Pre-built Binaries

Download the latest release from the [Releases](https://github.com/Sergeydigl3/zapret-discord-youtube-go/releases) page.

## Usage

### Basic Usage

```bash
# Run interactively
zapret

# Run with debug logging
zapret --debug

# Run in non-interactive mode
zapret --nointeractive
```

### Service Management

```bash
# Install as service
sudo zapret service install

# Start service
sudo zapret service start

# Stop service
sudo zapret service stop

# Check service status
sudo zapret service status

# Remove service
sudo zapret service remove
```

### Configuration Management

```bash
# Create configuration interactively
zapret config create

# Validate configuration
zapret config validate

# Show current configuration
zapret config show
```

### Debug Commands

```bash
# Show system information
zapret debug info

# Show firewall status
zapret debug firewall

# Show process status
zapret debug processes
```

## Configuration

The application uses a configuration file (`conf.yml`) and environment variables. Here's an example configuration:

```yaml
# Zapret Discord YouTube Go Edition - Configuration File
# This file contains the main configuration for the application

# Strategy file to use (relative to zapret-latest directory or absolute path)
strategy: general.bat

# Network interface to filter (use "any" for all interfaces)
interface: any

# Enable GameFilter to exclude game ports from filtering
gamefilter: false

# Path to nfqws binary (default: ./nfqws)
# nfqws_path: ./nfqws

# Enable debug logging
debug: false

# Run in non-interactive mode
nointeractive: false
```

### Environment Variables

All configuration options can also be set via environment variables with the `ZAPRET_` prefix:

```bash
ZAPRET_STRATEGY=general.bat \
ZAPRET_INTERFACE=enp0s3 \
ZAPRET_GAMEFILTER=true \
zapret
```

## Architecture

The Go edition follows a clean architecture with the following components:

- **Configuration Manager**: Handles config file and environment variables
- **Strategy Parser**: Parses BAT strategy files with generics support
- **Firewall Manager**: Manages nftables/iptables rules with context support
- **NFQWS Manager**: Manages nfqws processes and queues
- **Service Manager**: Handles service installation for multiple init systems
- **Logging System**: Structured logging with slog
- **Error Handling**: Comprehensive error handling with custom types

## Development

### Prerequisites

- Go 1.21+
- Make
- Docker (for container builds)

### Building

```bash
# Build for current platform
make build

# Build for all platforms
make build-all

# Run tests
make test

# Format code
make fmt

# Lint code
make lint
```

### Project Structure

```
go_edition/
├── cmd/
│   └── zapret/              # Main application
├── internal/
│   ├── config/             # Configuration management
│   ├── strategy/           # Strategy parsing
│   ├── firewall/           # Firewall management
│   ├── nfqws/              # NFQWS process management
│   ├── service/            # Service installation
│   ├── logging/            # Logging system
│   └── errors/             # Error handling
├── configs/                # Example configurations
├── scripts/                # Helper scripts
├── Dockerfile              # Docker configuration
├── Makefile                # Build automation
├── go.mod                  # Go module definition
└── README.md                # This file
```

## Migration from Bash Version

The Go edition is fully compatible with the original bash version:

1. **Configuration**: Uses YAML format (`conf.yml`)
2. **Strategy Files**: Supports the same BAT strategy files
3. **CLI Interface**: Provides identical command-line interface
4. **Service Installation**: Supports the same service installation methods

To migrate:

```bash
# Stop the old service
sudo systemctl stop zapret_discord_youtube

# Install the Go version
sudo make install

# Install as service
sudo zapret service install

# Start the new service
sudo zapret service start
```

## Performance Optimizations

The Go edition includes several performance optimizations:

- **Efficient File Parsing**: Buffered reading with minimal allocations
- **Concurrent Processing**: Parallel rule processing where possible
- **Context Management**: Proper timeout and cancellation handling
- **Memory Management**: Minimal memory allocations and reuse
- **Process Management**: Efficient process lifecycle management

## Contributing

Contributions are welcome! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch
3. Implement your changes
4. Write tests
5. Submit a pull request

### Code Standards

- Follow Go conventions and idioms
- Use proper error handling
- Write comprehensive documentation
- Include tests for new features
- Keep functions small and focused

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Support

For issues, questions, or suggestions:

- **Issues**: Report bugs and request features
- **Discussions**: Ask questions and share ideas
- **Pull Requests**: Contribute code improvements

## Acknowledgments

- Original bash version by [Sergeydigl3](https://github.com/Sergeydigl3)
- Strategy files from [Flowseal](https://github.com/Flowseal/zapret-discord-youtube)
- Go community for excellent libraries and tools

## Roadmap

- [x] Core functionality implementation
- [x] Configuration management
- [x] Strategy parsing with generics
- [x] Firewall management (nftables/iptables)
- [x] NFQWS process management
- [x] Service installation support
- [x] Structured logging
- [x] Comprehensive error handling
- [x] Docker support
- [x] Makefile automation
- [ ] Performance benchmarking
- [ ] Additional init system support
- [ ] Enhanced monitoring and metrics
- [ ] Web interface for management