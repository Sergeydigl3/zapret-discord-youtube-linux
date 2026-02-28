#!/usr/bin/env bash

# =============================================================================
# CLI: Настройка прав доступа
# =============================================================================

show_permissions_usage() {
    echo "Usage: $(basename "$0") setup-permissions [command]"
    echo
    echo "Настройка NOPASSWD для nft и nfqws."
    echo
    echo "Commands:"
    echo "    (без аргументов)  Создать /etc/sudoers.d/zapret"
    echo "    status            Показать текущие настройки"
    echo "    remove            Удалить настройки"
}

handle_permissions_command() {
    case "${1:-}" in
        status)
            show_permissions_status
            ;;
        remove)
            remove_permissions
            ;;
        -h|--help)
            show_permissions_usage
            ;;
        "")
            setup_permissions
            ;;
        *)
            echo "Unknown command: $1"
            show_permissions_usage
            exit 1
            ;;
    esac
}
