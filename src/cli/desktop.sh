#!/usr/bin/env bash

# =============================================================================
# CLI: Управление desktop ярлыком
# =============================================================================

# Справка для desktop
show_desktop_usage() {
    echo "Usage: $(basename "$0") desktop <command>"
    echo
    echo "Commands:"
    echo "    install     Create desktop shortcut in applications menu"
    echo "    remove      Remove desktop shortcut from applications menu"
}

# Подменю управления desktop ярлыком
show_desktop_menu() {
    echo ""
    echo "=== Управление desktop ярлыком ==="
    echo "1. Создать ярлык в меню приложений"
    echo "2. Удалить ярлык из меню приложений"
    echo "0. Назад"
    read -p "Выберите действие: " choice
    case $choice in
    1)
        create_desktop_shortcut
        read -p "Нажмите Enter для продолжения..."
        ;;
    2)
        remove_desktop_shortcut
        read -p "Нажмите Enter для продолжения..."
        ;;
    0) return ;;
    *)
        echo "Неверный выбор."
        ;;
    esac
}

# Обработчик команды desktop
handle_desktop_command() {
    case "${1:-}" in
        install)
            create_desktop_shortcut
            ;;
        remove)
            remove_desktop_shortcut
            ;;
        -h|--help|"")
            show_desktop_usage
            ;;
        *)
            echo "Unknown desktop command: $1"
            show_desktop_usage
            exit 1
            ;;
    esac
}
