#!/usr/bin/env bash

# Константы путей
HOME_DIR_PATH="$(realpath "$(dirname "$0")")"
BASE_DIR="$HOME_DIR_PATH"
CONF_FILE="$HOME_DIR_PATH/conf.env"
CUSTOM_STRATEGIES_DIR="$HOME_DIR_PATH/custom-strategies"
REPO_DIR="$HOME_DIR_PATH/zapret-latest"
NFQWS_PATH="$HOME_DIR_PATH/nfqws"

# Подключаем общие библиотеки
source "$HOME_DIR_PATH/lib/constants.sh"
source "$HOME_DIR_PATH/lib/common.sh"
source "$HOME_DIR_PATH/lib/download.sh"
source "$HOME_DIR_PATH/lib/desktop.sh"
source "$HOME_DIR_PATH/init-backends/init.sh"

# Функция для интерактивного создания файла конфигурации conf.env
create_conf_file() {
    # Определяем режим работы
    if [[ -f "$CONF_FILE" ]]; then
        echo "Изменение конфигурации..."
        local is_editing=true
    else
        echo "Конфигурация отсутствует или неполная. Создаем новый конфиг."
        local is_editing=false
    fi

    # 1. Выбор интерфейса
    local interfaces=("any" $(ls /sys/class/net))
    if [ ${#interfaces[@]} -eq 0 ]; then
        handle_error "Не найдены сетевые интерфейсы"
    fi
    echo "Доступные сетевые интерфейсы:"
    select chosen_interface in "${interfaces[@]}"; do
        if [ -n "$chosen_interface" ]; then
            echo "Выбран интерфейс: $chosen_interface"
            break
        fi
        echo "Неверный выбор. Попробуйте еще раз."
    done

    # 2. Gamefilter
    read -p "Включить Gamefilter? [y/N] [n]: " enable_gamefilter
    if [[ "$enable_gamefilter" =~ ^[Yy1] ]]; then
        gamefilter_choice="true"
    else
        gamefilter_choice="false"
    fi

    # 3. Выбор стратегии
    select_strategy_interactive
    local strategy_choice="$selected_strategy"

    # Записываем полученные значения в conf.env
    cat <<EOF >"$CONF_FILE"
interface=$chosen_interface
gamefilter=$gamefilter_choice
strategy=$strategy_choice
EOF

    if [[ "$is_editing" == true ]]; then
        echo "Конфигурация обновлена."

        # Если сервис активен, предлагаем перезапустить
        check_service_status >/dev/null 2>&1
        if [ $? -eq 2 ]; then
            read -p "Сервис активен. Перезапустить сервис для применения новых настроек? (Y/n): " answer
            if [[ ${answer:-Y} =~ ^[Yy]$ ]]; then
                restart_service
            fi
        fi
    else
        echo "Конфигурация записана в $CONF_FILE."
    fi
}

# Подменю управления сервисом
show_service_menu() {
    check_service_status
    local status=$?

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

    check_dependencies

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

# Функция для вывода текущей конфигурации
show_config() {
    if [ -f "$CONF_FILE" ]; then
        echo "Текущая конфигурация:"
        echo
        cat "$CONF_FILE"
        echo
    else
        echo "Файл конфигурации отсутствует"
    fi
}

# Функция для обновления конфигурации с рестартом сервиса.
update_config() {
    local strategy="$1"
    local interface="${2:-any}"
    local gamefilter="$3"

    # Валидация и нормализация названия стратегии (функция из lib/common.sh)
    local normalized_strategy
    if ! normalized_strategy=$(normalize_strategy "$strategy"); then
        echo "Несуществующая стратегия!"
        show_strategies
        exit 1
    fi

    if [[ "$interface" != "any" ]]; then
        interface_match=$(ls /sys/class/net | grep -E "^${interface}$")
        if [ ! -n "$interface_match" ]; then
            echo "Несуществующий интерфейс!"
            local interfaces=("any" $(ls /sys/class/net))
            echo "Доступные интерфейсы: ${interfaces[@]}"
            exit 1
        fi
    fi

    cat > "$CONF_FILE" << ENV
interface=${interface}
gamefilter=${gamefilter}
strategy=${normalized_strategy}
ENV

    echo "Конфигурация обновлена."
    show_config

    if [ "$RESTART_SERVICE" = true ]; then
        restart_service
    fi
}

# Запуск демона (вызывается из сервиса)
# Использует run_zapret_command с конфигом
run_daemon() {
    run_zapret_command --config "$CONF_FILE"
}

# Остановка zapret (nfqws + nftables)
stop_zapret() {
    source "$BASE_DIR/lib/firewall.sh"
    log "Остановка nfqws..."
    stop_nfqws
    log "Очистка правил nftables..."
    nft_clear
    log "Очистка завершена."
}

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

# Справка для config
show_config_usage() {
    echo "Usage: $(basename "$0") config <command> [options]"
    echo
    echo "Commands:"
    echo "    show                         Show current configuration"
    echo "    edit                         Interactive configuration editor"
    echo "    set <STRATEGY> [INTERFACE]   Set configuration"
    echo
    echo "Options for 'set':"
    echo "    -g, --gamefilter    Enable gamefilter"
    echo "    -n, --norestart     Do not restart the service"
    echo
    echo "Examples:"
    echo "    $(basename "$0") config show"
    echo "    $(basename "$0") config set discord"
    echo "    $(basename "$0") config set discord eth0 -g"
}

# Справка для strategy
show_strategy_usage() {
    echo "Usage: $(basename "$0") strategy <command>"
    echo
    echo "Commands:"
    echo "    list        List available strategies"
}

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

# Обработчик команды service
handle_service_command() {
    case "${1:-}" in
        status)
            check_service_status
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

# Обработчик команды config
handle_config_command() {
    case "${1:-}" in
        show)
            show_config
            ;;
        edit)
            create_conf_file
            ;;
        set)
            shift
            # Парсинг флагов для set
            local gamefilter=false
            local restart_svc=true
            local strategy=""
            local iface="any"

            while [[ $# -gt 0 ]]; do
                case $1 in
                    -g|--gamefilter)
                        gamefilter=true
                        shift
                        ;;
                    -n|--norestart)
                        restart_svc=false
                        shift
                        ;;
                    -*)
                        echo "Unknown option: $1"
                        show_config_usage
                        exit 1
                        ;;
                    *)
                        if [[ -z "$strategy" ]]; then
                            strategy="$1"
                        elif [[ "$iface" == "any" ]]; then
                            iface="$1"
                        else
                            echo "Too many arguments"
                            show_config_usage
                            exit 1
                        fi
                        shift
                        ;;
                esac
            done

            if [[ -z "$strategy" ]]; then
                echo "Error: strategy is required"
                show_config_usage
                exit 1
            fi

            RESTART_SERVICE=$restart_svc
            update_config "$strategy" "$iface" "$gamefilter"
            ;;
        -h|--help|"")
            show_config_usage
            ;;
        *)
            echo "Unknown config command: $1"
            show_config_usage
            exit 1
            ;;
    esac
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

    check_dependencies

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

# Глобальные переменные для config set
RESTART_SERVICE=true

# Главный парсер команд
case "${1:-}" in
    # Подкоманды
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
