#!/usr/bin/env bash

# =============================================================================
# CLI: Главное меню и справка
# =============================================================================

# Главная справка
show_usage() {
    echo "Usage: $(basename "$0") <command> [options]"
    echo
    echo "Commands:"
    echo "    service        Manage the system service"
    echo "    config         Manage configuration"
    echo "    strategy       Manage strategies"
    echo "    download-deps  Download/update dependencies (zapret + strategies)"
    echo "    desktop        Manage desktop shortcut"
    echo "    run            Run interactively (without installing service)"
    echo
    echo "Internal commands:"
    echo "    daemon         Run zapret daemon (called by service)"
    echo "    kill           Stop nfqws and clear nftables"
    echo
    echo "Run '$(basename "$0") <command> --help' for command-specific help."
    echo
    echo "Examples:"
    echo "    $(basename "$0") service install"
    echo "    $(basename "$0") config set discord"
    echo "    $(basename "$0") strategy list"
    echo "    $(basename "$0") download-deps"
    echo "    $(basename "$0") desktop install"
    echo "    $(basename "$0") run -s discord"
}

# Основное меню управления
show_menu() {
    echo ""
    echo "1. Запустить (без установки сервиса)"
    echo "2. Управление сервисом"
    echo "3. Изменить конфигурацию"
    echo "4. Управление зависимостями"
    echo "5. Управление desktop ярлыком"
    echo "0. Выход"
    read -p "Выберите действие: " choice
    case $choice in
    1) run_zapret_command ;;
    2) show_service_menu ;;
    3) create_conf_file ;;
    4) show_dependencies_menu ;;
    5) show_desktop_menu ;;
    0) exit 0 ;;
    *)
        echo "Неверный выбор."
        ;;
    esac
}

# Запуск интерактивного меню
run_interactive() {
    show_menu
    echo ""
    read -p "Нажмите Enter для выхода..."
}
