#!/usr/bin/env bash

# =============================================================================
# CLI: Управление сервисом
# =============================================================================

# Справка для service
show_service_usage() {
    echo "Usage: $(basename "$0") service <command>"
    echo
    echo "Commands:"
    echo "    status      Show service status"
    echo "    install     Install and start service"
    echo "    remove      Remove service completely"
    echo "    start       Start service"
    echo "    stop        Stop service"
    echo "    restart     Restart service"
}

# Подменю управления сервисом
show_service_menu() {
    local status=0
    check_service_status || status=$?

    echo ""
    case $status in
    1)
        echo "1. Установить и запустить сервис"
        echo "0. Назад"
        read -p "Выберите действие: " choice
        case $choice in
        1) ensure_config_exists && install_service ;;
        0) return ;;
        esac
        ;;
    2)
        echo "1. Остановить сервис"
        echo "2. Перезапустить сервис"
        echo "3. Удалить сервис"
        echo "0. Назад"
        read -p "Выберите действие: " choice
        case $choice in
        1) stop_service ;;
        2) restart_service ;;
        3) remove_service ;;
        0) return ;;
        esac
        ;;
    3)
        echo "1. Запустить сервис"
        echo "2. Удалить сервис"
        echo "0. Назад"
        read -p "Выберите действие: " choice
        case $choice in
        1) start_service ;;
        2) remove_service ;;
        0) return ;;
        esac
        ;;
    esac
}

# Обработчик команды service
handle_service_command() {
    case "${1:-}" in
        status)
            check_service_status || true
            ;;
        install)
            ensure_config_exists && install_service
            ;;
        remove)
            remove_service
            ;;
        start)
            start_service
            ;;
        stop)
            stop_service
            ;;
        restart)
            restart_service
            ;;
        -h|--help)
            show_service_usage
            ;;
        "")
            show_service_menu
            ;;
        *)
            echo "Unknown service command: $1"
            show_service_usage
            exit 1
            ;;
    esac
}
