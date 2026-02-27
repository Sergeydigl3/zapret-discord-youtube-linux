#!/usr/bin/env bash

set -e

# Константы путей
HOME_DIR_PATH="$(realpath "$(dirname "$0")")"
BASE_DIR="$HOME_DIR_PATH"
CONF_FILE="$HOME_DIR_PATH/conf.env"
CUSTOM_STRATEGIES_DIR="$HOME_DIR_PATH/custom-strategies"
REPO_DIR="$HOME_DIR_PATH/zapret-latest"
NFQWS_PATH="$HOME_DIR_PATH/nfqws"

# Подключаем библиотеки
source "$HOME_DIR_PATH/src/lib/elevate.sh"
source "$HOME_DIR_PATH/src/lib/constants.sh"
source "$HOME_DIR_PATH/src/lib/common.sh"
source "$HOME_DIR_PATH/src/lib/download.sh"
source "$HOME_DIR_PATH/src/lib/desktop.sh"
source "$HOME_DIR_PATH/src/lib/permissions.sh"

# Подключаем CLI модули
source "$HOME_DIR_PATH/src/cli/menu.sh"
source "$HOME_DIR_PATH/src/cli/service.sh"
source "$HOME_DIR_PATH/src/cli/config.sh"
source "$HOME_DIR_PATH/src/cli/strategy.sh"
source "$HOME_DIR_PATH/src/cli/download.sh"
source "$HOME_DIR_PATH/src/cli/desktop.sh"
source "$HOME_DIR_PATH/src/cli/run.sh"
source "$HOME_DIR_PATH/src/cli/permissions.sh"

check_dependencies

# Главный парсер команд
case "${1:-}" in
    service)
        shift
        handle_service_command "$@"
        ;;
    config)
        shift
        handle_config_command "$@"
        ;;
    strategy)
        shift
        handle_strategy_command "$@"
        ;;
    download-deps)
        shift
        handle_download_deps_command "$@"
        ;;
    desktop)
        shift
        handle_desktop_command "$@"
        ;;
    run)
        shift
        run_zapret_command "$@"
        ;;
    daemon)
        run_daemon
        ;;
    kill)
        stop_zapret
        ;;
    setup-permissions)
        shift
        handle_permissions_command "$@"
        ;;
    -h|--help|help)
        show_usage
        ;;
    "")
        run_interactive
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run '$(basename "$0") --help' for usage information."
        exit 1
        ;;
esac
