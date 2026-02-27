#!/usr/bin/env bash

# =============================================================================
# CLI: Загрузка зависимостей
# =============================================================================

# Справка для download-deps
show_download_deps_usage() {
    echo "Usage: $(basename "$0") download-deps [options]"
    echo
    echo "Download/update zapret (nfqws) and strategies repositories."
    echo
    echo "Options:"
    echo "    -d, --default               Use recommended versions (non-interactive)"
    echo "    -z, --zapret-version VER    Zapret version (e.g., v72.9)"
    echo "    -s, --strat-version VER     Strategy version (commit hash or tag)"
    echo "    -h, --help                  Show this help"
    echo
    echo "Examples:"
    echo "    $(basename "$0") download-deps                    # Interactive mode"
    echo "    $(basename "$0") download-deps --default          # Use recommended versions"
    echo "    $(basename "$0") download-deps -z v72.9 -s master   # Specific versions"
}

# Подменю управления зависимостями
show_dependencies_menu() {
    echo ""
    echo "=== Управление зависимостями ==="
    echo "1. Скачать зависимости (интерактивный выбор версий)"
    echo "2. Скачать рекомендованные версии"
    echo "3. Показать список стратегий"
    echo "0. Назад"
    read -p "Выберите действие: " choice
    case $choice in
    1)
        handle_download_deps_command
        ;;
    2)
        handle_download_deps_command --default
        ;;
    3)
        show_strategies
        read -p "Нажмите Enter для продолжения..."
        ;;
    0) return ;;
    *)
        echo "Неверный выбор."
        ;;
    esac
}

# Обработчик команды download-deps
handle_download_deps_command() {
    local zapret_version=""
    local strat_version=""
    local interactive=true
    local use_defaults=false

    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            -z|--zapret-version)
                zapret_version="$2"
                interactive=false
                shift 2
                ;;
            -s|--strat-version)
                strat_version="$2"
                interactive=false
                shift 2
                ;;
            -d|--default)
                use_defaults=true
                interactive=false
                shift
                ;;
            -h|--help)
                show_download_deps_usage
                return 0
                ;;
            *)
                echo "Unknown option: $1"
                show_download_deps_usage
                return 1
                ;;
        esac
    done

    # Режим с флагом --default
    if [[ "$use_defaults" == true ]]; then
        echo "Загрузка зависимостей (рекомендованные версии)"
        echo ""
        zapret_version="$ZAPRET_RECOMMENDED_VERSION"
        strat_version="$MAIN_REPO_REV"
    # Интерактивный режим - спрашиваем версии
    elif [[ "$interactive" == true ]]; then
        echo "Загрузка зависимостей (nfqws + стратегии)"
        echo ""

        # Выбор версии zapret
        select_zapret_version_interactive
        zapret_version="$selected_zapret_version"

        echo ""

        # Выбор версии стратегий
        select_strategy_version_interactive
        strat_version="$selected_strat_version"
    else
        zapret_version="${zapret_version:-$ZAPRET_RECOMMENDED_VERSION}"
        strat_version="${strat_version:-$MAIN_REPO_REV}"
    fi

    echo ""
    echo "Загрузка nfqws (version: $zapret_version)..."
    download_nfqws "$zapret_version"

    echo ""
    echo "Загрузка стратегий (version: $strat_version)..."

    # Устанавливаем глобальный флаг интерактивности для setup_repository
    INTERACTIVE_MODE="$interactive"
    setup_repository "$strat_version"

    echo ""
    echo "Зависимости успешно загружены."
}
