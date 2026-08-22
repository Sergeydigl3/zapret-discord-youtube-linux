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
    echo "    test-strategies  Test strategies (connectivity checks)"
    echo "    setup-permissions  Setup NOPASSWD for nft/iptables/nfqws"
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
    clear
    echo "░▒▓████████▓▒░░▒▓██████▓▒░░▒▓███████▓▒░░▒▓███████▓▒░░▒▓████████▓▒░▒▓████████▓▒░ "
    echo "       ░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░         ░▒▓█▓▒░     "
    echo "     ░▒▓██▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░         ░▒▓█▓▒░     "
    echo "   ░▒▓██▓▒░  ░▒▓████████▓▒░▒▓███████▓▒░░▒▓███████▓▒░░▒▓██████▓▒░    ░▒▓█▓▒░     "
    echo " ░▒▓██▓▒░    ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░         ░▒▓█▓▒░     "
    echo "░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░         ░▒▓█▓▒░     "
    echo "░▒▓████████▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓████████▓▒░  ░▒▓█▓▒░     "
    echo "=============================================================================="
    echo "1) Запустить (без установки сервиса)"
    echo "2) Управление сервисом"
    echo "3) Изменить конфигурацию"
    echo "4) Управление зависимостями"
    echo "5) Управление ярлыком на рабочем столе"
    echo "6) Настроить работу без пароля"
    echo "7) Сменить режим ipset [Текущий - $(get_mode_ipset)]"
    echo "8) Тест стратегий (проверка Discord/YouTube и др.)"
    echo "0) Выход"
    echo "=============================================================================="
    echo ""
    read -p "Выберите действие: " choice
     case $choice in
    1) run_zapret_command || show_error "Не удалось запустить zapret" ;;
    2) show_service_menu ;;
    3) create_conf_file || show_error "Не удалось создать конфигурацию"
       read -p "Нажмите Enter для продолжения..." ;;
    4) show_dependencies_menu ;;
    5) show_desktop_menu ;;
    6) setup_permissions || show_error "Не удалось настроить разрешения" ;;
    7) change_mode_ipset "$(get_mode_ipset)" || show_error "Не удалось сменить режим ipset" ;;
    8) run_test_strategies_from_menu || show_error "Не удалось запустить тест стратегий" ;;
    0) exit 0 ;;
    *) show_error "Неверный выбор" ;;
    esac
}

run_test_strategies_from_menu() {
    local test_script="$BASE_DIR/test_strategies.sh"
    if [[ ! -f "$test_script" ]]; then
        echo "Не найден: $test_script"
        read -r -p "Enter..."
        return
    fi
    if [[ $EUID -ne 0 ]]; then
        exec sudo "$test_script" --interactive
    fi
    # shellcheck source=/dev/null
    source "$test_script"
    run_test_interactive_menu
}

# Запуск интерактивного меню
run_interactive() {
    while true; do
        show_menu
    done
    echo ""
    read -p "Нажмите Enter для выхода..."
}