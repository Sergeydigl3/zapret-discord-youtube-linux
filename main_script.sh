#!/usr/bin/env bash

set -e

# Константы путей
BASE_DIR="$(realpath "$(dirname "$0")")"
REPO_DIR="$BASE_DIR/zapret-latest"
CUSTOM_DIR="./custom-strategies"
CUSTOM_STRATEGIES_DIR="$BASE_DIR/custom-strategies"
NFQWS_PATH="$BASE_DIR/nfqws"
CONF_FILE="$BASE_DIR/conf.env"
STOP_SCRIPT="$BASE_DIR/stop_and_clean_nft.sh"

# Подключаем общие библиотеки
source "$BASE_DIR/lib/constants.sh"
source "$BASE_DIR/lib/common.sh"

# Флаги
DEBUG=false
NOINTERACTIVE=false
USE_GAME_FILTER=false

_term() {
    sudo /usr/bin/env bash $STOP_SCRIPT
}

# Функция для поиска bat файлов внутри репозитория
find_bat_files() {
    local pattern="$1"
    find "." -type f -name "$pattern" -print0
}

# Функция для выбора стратегии
select_strategy() {
    # Сначала собираем кастомные файлы
    local custom_files=()
    if [ -d "$CUSTOM_DIR" ]; then
        cd "$CUSTOM_DIR" && custom_files=($(ls *.bat 2>/dev/null)) && cd ..
    fi

    cd "$REPO_DIR" || handle_error "Не удалось перейти в директорию $REPO_DIR"

    if $NOINTERACTIVE; then
        if [ ! -f "$strategy" ] && [ ! -f "../$CUSTOM_DIR/$strategy" ]; then
            handle_error "Указанный .bat файл стратегии $strategy не найден"
        fi
        # Проверяем, где лежит файл, чтобы распарсить
        [ -f "$strategy" ] && parse_bat_file "$strategy" || parse_bat_file "../$CUSTOM_DIR/$strategy"
        cd ..
        return
    fi

    # Собираем стандартные файлы
    local IFS=$'\n'
    local repo_files=($(find_bat_files "general*.bat" | xargs -0 -n1 echo) $(find_bat_files "discord.bat" | xargs -0 -n1 echo))

    # Объединяем списки (кастомные будут первыми)
    local bat_files=("${custom_files[@]}" "${repo_files[@]}")

    if [ ${#bat_files[@]} -eq 0 ]; then
        cd ..
        handle_error "Не найдены подходящие .bat файлы"
    fi

    echo "Доступные стратегии:"
    select strategy in "${bat_files[@]}"; do
        if [ -n "$strategy" ]; then
            log "Выбрана стратегия: $strategy"

            # Определяем полный путь для парсера перед выходом из папки
            local final_path=""
            if [ -f "$strategy" ]; then
                final_path="$REPO_DIR/$strategy"
            else
                final_path="$REPO_DIR/../$CUSTOM_DIR/$strategy"
            fi

            cd ..
            parse_bat_file "$final_path"
            break
        fi
        echo "Неверный выбор. Попробуйте еще раз."
    done
}

# Функция парсинга параметров из bat файла
parse_bat_file() {
    local file="$1"
    local bin_path="bin/"
    debug_log "Parsing .bat file: $file"

    # Читаем весь файл целиком
    local content=$(cat "$file" | tr -d '\r')

    debug_log "File content loaded"

    # Заменяем переменные
    content="${content//%BIN%/$bin_path}"
    content="${content//%LISTS%/lists/}"

    # Обрабатываем GameFilter
    if [ "$USE_GAME_FILTER" = true ]; then
        content="${content//%GameFilter%/$GAME_FILTER_PORTS}"
    else
        content="${content//,%GameFilter%/}"
        content="${content//%GameFilter%,/}"
    fi

    # Ищем --wf-tcp и --wf-udp
    local wf_tcp_count=$(echo "$content" | grep -oP -- '--wf-tcp=' | wc -l)
    local wf_udp_count=$(echo "$content" | grep -oP -- '--wf-udp=' | wc -l)

    # Проверяем количество вхождений
    if [ "$wf_tcp_count" -eq 0 ] || [ "$wf_udp_count" -eq 0 ]; then
        echo "ERROR: --wf-tcp or --wf-udp not found in $file"
        exit 1
    fi

    if [ "$wf_tcp_count" -gt 1 ]; then
        echo "ERROR: Multiple --wf-tcp entries found in $file (found: $wf_tcp_count)"
        exit 1
    fi

    if [ "$wf_udp_count" -gt 1 ]; then
        echo "ERROR: Multiple --wf-udp entries found in $file (found: $wf_udp_count)"
        exit 1
    fi

    # Извлекаем порты
    tcp_ports=$(echo "$content" | grep -oP -- '--wf-tcp=\K[0-9,-]+' | head -n1)
    udp_ports=$(echo "$content" | grep -oP -- '--wf-udp=\K[0-9,-]+' | head -n1)

    debug_log "TCP ports: $tcp_ports"
    debug_log "UDP ports: $udp_ports"

    # Парсим с помощью grep -oP (Perl regex)
    while IFS= read -r match; do
        if [[ "$match" =~ --filter-(tcp|udp)=([0-9,%-]+)[[:space:]]+(.*) ]]; then
            local protocol="${BASH_REMATCH[1]}"
            local ports="${BASH_REMATCH[2]}"
            local nfqws_args="${BASH_REMATCH[3]}"

            # Очищаем лишние пробелы
            nfqws_args=$(echo "$match" | xargs)
            nfqws_args="${nfqws_args//=^!/=!}"

            nfqws_params+=("$nfqws_args")
            debug_log "Matched protocol: $protocol, ports: $ports"
            debug_log "NFQWS parameters: $nfqws_args"
        fi
    done < <(echo "$content" | grep -oP -- '--filter-(tcp|udp)=([0-9,-]+)\s+(?:[\s\S]*?--new|.*)')
}

# Функция настройки nftables
setup_nftables() {
    local interface="$1"

    log "Настройка nftables с очисткой только помеченных правил..."

    # Удаляем существующую таблицу, если она была создана этим скриптом
    if sudo nft list tables | grep -q "$NFT_TABLE"; then
        sudo nft flush chain $NFT_TABLE $NFT_CHAIN
        sudo nft delete chain $NFT_TABLE $NFT_CHAIN
        sudo nft delete table $NFT_TABLE
    fi

    # Добавляем таблицу и цепочку
    sudo nft add table $NFT_TABLE
    sudo nft add chain $NFT_TABLE $NFT_CHAIN { type filter hook output priority 0\; }

    local oif_clause=""
    if [ -n "$interface" ] && [ "$interface" != "any" ]; then
        oif_clause="oifname \"$interface\""
    fi

    # Добавляем правило для TCP портов (если есть)
    if [ -n "$tcp_ports" ]; then
        sudo nft add rule $NFT_TABLE $NFT_CHAIN $oif_clause meta mark != $NFT_MARK tcp dport {$tcp_ports} counter queue num $NFT_QUEUE_NUM bypass comment \"$NFT_RULE_COMMENT\" ||
            handle_error "Ошибка при добавлении TCP правила nftables"
        log "Добавлено TCP правило для портов: $tcp_ports -> queue $NFT_QUEUE_NUM"
    fi

    # Добавляем правило для UDP портов (если есть)
    if [ -n "$udp_ports" ]; then
        sudo nft add rule $NFT_TABLE $NFT_CHAIN $oif_clause meta mark != $NFT_MARK udp dport {$udp_ports} counter queue num $NFT_QUEUE_NUM bypass comment \"$NFT_RULE_COMMENT\" ||
            handle_error "Ошибка при добавлении UDP правила nftables"
        log "Добавлено UDP правило для портов: $udp_ports -> queue $NFT_QUEUE_NUM"
    fi
}

# Функция запуска nfqws
start_nfqws() {
    log "Запуск процесса nfqws..."
    sudo pkill -f nfqws
    cd "$REPO_DIR" || handle_error "Не удалось перейти в директорию $REPO_DIR"

    local full_params=""
    for params in "${nfqws_params[@]}"; do
        full_params="$full_params $params"
    done

    debug_log "Запуск nfqws с параметрами: $NFQWS_PATH --daemon --dpi-desync-fwmark=$NFT_MARK --qnum=$NFT_QUEUE_NUM $full_params"
    eval "sudo $NFQWS_PATH --daemon --dpi-desync-fwmark=$NFT_MARK --qnum=$NFT_QUEUE_NUM $full_params" ||
        handle_error "Ошибка при запуске nfqws"
}

# Основная функция
main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
        -debug)
            DEBUG=true
            shift
            ;;
        -nointeractive)
            NOINTERACTIVE=true
            shift
            load_config "$CONF_FILE"
            ;;
        *)
            break
            ;;
        esac
    done

    check_dependencies
    setup_repository

    # Включение GameFilter
    if $NOINTERACTIVE; then
        _term
        sleep 1

        if [ "$gamefilter" == "true" ]; then
            USE_GAME_FILTER=true
            log "GameFilter включен"
        else
            USE_GAME_FILTER=false
            log "GameFilter выключен"
        fi
    else
        echo ""
        read -p "Включить GameFilter? [y/N]:" enable_gamefilter
        if [[ "$enable_gamefilter" =~ ^[Yy1] ]]; then
            USE_GAME_FILTER=true
            log "GameFilter включен"
        else
            USE_GAME_FILTER=false
            log "GameFilter выключен"
        fi
    fi

    if $NOINTERACTIVE; then
        select_strategy
        setup_nftables "$interface"
    else
        select_strategy
        local interfaces=("any" $(ls /sys/class/net))
        if [ ${#interfaces[@]} -eq 0 ]; then
            handle_error "Не найдены сетевые интерфейсы"
        fi
        echo "Доступные сетевые интерфейсы:"
        select interface in "${interfaces[@]}"; do
            if [ -n "$interface" ]; then
                log "Выбран интерфейс: $interface"
                break
            fi
            echo "Неверный выбор. Попробуйте еще раз."
        done
        setup_nftables "$interface"
    fi
    start_nfqws
    log "Настройка успешно завершена"

    # Пауза перед выходом
    if ! $NOINTERACTIVE; then
        echo "Нажмите Ctrl+C для завершения..."
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _term
    # Запуск скрипта
    main "$@"

    trap _term SIGINT

    sleep infinity &
    wait
fi
