#!/usr/bin/env bash

# =============================================================================
# CLI: Управление стратегиями
# =============================================================================

# Справка для strategy
show_strategy_usage() {
    echo "Usage: $(basename "$0") strategy <command>"
    echo
    echo "Commands:"
    echo "    list        List available strategies"
}

# Обработчик команды strategy
handle_strategy_command() {
    case "${1:-}" in
        list)
            show_strategies
            ;;
        -h|--help|"")
            show_strategy_usage
            ;;
        *)
            echo "Unknown strategy command: $1"
            show_strategy_usage
            exit 1
            ;;
    esac
}
