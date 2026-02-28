#!/usr/bin/env bash

# =============================================================================
# CLI: Управление конфигурацией
# =============================================================================

# Глобальные переменные для config set
RESTART_SERVICE=true

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
        local svc_status=0
        check_service_status >/dev/null 2>&1 || svc_status=$?
        if [ $svc_status -eq 2 ]; then
            read -p "Сервис активен. Перезапустить сервис для применения новых настроек? (Y/n): " answer
            if [[ ${answer:-Y} =~ ^[Yy]$ ]]; then
                restart_service
            fi
        fi
    else
        echo "Конфигурация записана в $CONF_FILE."
    fi
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

# Функция для обновления конфигурации с рестартом сервиса
update_config() {
    local strategy="$1"
    local interface="${2:-any}"
    local gamefilter="$3"

    # Валидация и нормализация названия стратегии
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
