#!/usr/bin/env bash

# =============================================================================
# CLI: Запуск zapret
# =============================================================================

# Справка для run
show_run_usage() {
    echo "Usage: $(basename "$0") run [options]"
    echo
    echo "Run zapret in foreground (useful for testing)."
    echo
    echo "Options:"
    echo "    -c, --config FILE       Load configuration from file"
    echo "    -s, --strategy NAME     Use specific strategy"
    echo "    -i, --interface NAME    Network interface (default: any)"
    echo "    -g, --gamefilter        Enable gamefilter"
    echo "    -h, --help              Show this help"
    echo
    echo "Modes:"
    echo "    1. Interactive mode (no options):"
    echo "       $(basename "$0") run"
    echo "       Prompts for all parameters"
    echo
    echo "    2. Load from config file:"
    echo "       $(basename "$0") run --config conf.env"
    echo "       Uses existing configuration file"
    echo
    echo "    3. Direct parameters:"
    echo "       $(basename "$0") run -s discord -i eth0 -g"
    echo "       Specify all parameters directly"
}

# Унифицированная команда запуска zapret
# Поддерживает 3 режима:
# 1. Интерактивный: service.sh run
# 2. Из конфига: service.sh run --config conf.env
# 3. Прямые параметры: service.sh run -s discord -i eth0 -g
run_zapret_command() {
    local use_config=""
    local use_strategy=""
    local use_interface="any"
    local use_gamefilter="false"
    local interactive=true

    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                use_config="$2"
                interactive=false
                shift 2
                ;;
            -s|--strategy)
                use_strategy="$2"
                interactive=false
                shift 2
                ;;
            -i|--interface)
                use_interface="$2"
                shift 2
                ;;
            -g|--gamefilter)
                use_gamefilter="true"
                shift
                ;;
            -h|--help)
                show_run_usage
                return 0
                ;;
            *)
                echo "Unknown option: $1"
                show_run_usage
                return 1
                ;;
        esac
    done

    # Проверяем наличие репозитория со стратегиями
    if [[ ! -d "$REPO_DIR" ]]; then
        echo "Ошибка: репозиторий со стратегиями не найден."
        echo "Запустите: ./service.sh download-deps --default"
        return 1
    fi

    # Режим 1: Загрузка из конфига
    if [[ -n "$use_config" ]]; then
        if [[ ! -f "$use_config" ]]; then
            echo "Error: config file not found: $use_config"
            return 1
        fi
        echo "Загрузка конфигурации из: $use_config"
        load_config "$use_config"

    # Режим 2: Прямые параметры
    elif [[ -n "$use_strategy" ]]; then
        echo "Запуск с параметрами: strategy=$use_strategy, interface=$use_interface, gamefilter=$use_gamefilter"
        strategy="$use_strategy"
        interface="$use_interface"
        gamefilter="$use_gamefilter"

    # Режим 3: Интерактивный выбор
    elif [[ "$interactive" == true ]]; then
        echo "Интерактивный запуск zapret"
        echo ""

        # Выбор интерфейса
        local interfaces=("any" $(ls /sys/class/net))
        echo "Доступные сетевые интерфейсы:"
        select interface in "${interfaces[@]}"; do
            if [ -n "$interface" ]; then
                echo "Выбран интерфейс: $interface"
                break
            fi
            echo "Неверный выбор. Попробуйте еще раз."
        done

        # Gamefilter
        read -p "Включить Gamefilter? [y/N]: " enable_gf
        if [[ "$enable_gf" =~ ^[Yy1] ]]; then
            gamefilter="true"
        else
            gamefilter="false"
        fi

        # Выбор стратегии
        select_strategy_interactive
        strategy="$selected_strategy"
    fi

    # Запуск zapret
    run_zapret

    echo ""
    echo "zapret запущен. Нажмите Ctrl+C для завершения..."
    trap 'stop_zapret; exit 0' SIGTERM SIGINT
    sleep infinity &
    wait
}

# Запуск демона (вызывается из сервиса)
# Использует run_zapret_command с конфигом
run_daemon() {
    run_zapret_command --config "$CONF_FILE"
}

# Остановка zapret (nfqws + nftables)
stop_zapret() {
    source "$BASE_DIR/src/lib/firewall.sh"
    log "Остановка nfqws..."
    stop_nfqws
    log "Очистка правил nftables..."
    nft_clear
    log "Очистка завершена."
}
