#!/usr/bin/env bash

set -e

# Константы
BASE_DIR="$(realpath "$(dirname "$0")")"
REPO_DIR="$BASE_DIR/zapret-latest"
CUSTOM_DIR="./custom-strategies"
REPO_URL="https://github.com/Flowseal/zapret-discord-youtube"
NFQWS_PATH="$BASE_DIR/nfqws"
CONF_FILE="$BASE_DIR/conf.env"
STOP_SCRIPT="$BASE_DIR/stop_and_clean_nft.sh"
MAIN_REPO_REV="e1322fd3afe57ca14f4d79b7ac5f92e4513cd0f3"

# Флаг отладки
DEBUG=false
NOINTERACTIVE=false

# GameFilter
GAME_FILTER_PORTS="1024-65535"
USE_GAME_FILTER=false

_term() {
    sudo /usr/bin/env bash $STOP_SCRIPT
}
_term

# Функция для логирования
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Функция отладочного логирования
debug_log() {
    if $DEBUG; then
        echo "[DEBUG] $1"
    fi
}

# Функция обработки ошибок
handle_error() {
    log "Ошибка: $1"
    exit 1
}

# Функция для проверки наличия необходимых утилит
check_dependencies() {
    local deps=("git" "nft" "grep" "sed")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            handle_error "Не установлена утилита $dep"
        fi
    done
}

# Функция чтения конфигурационного файла
load_config() {
    if [ ! -f "$CONF_FILE" ]; then
        handle_error "Файл конфигурации $CONF_FILE не найден"
    fi
    
    # Чтение переменных из конфигурационного файла
    source "$CONF_FILE"
    
    # Проверка обязательных переменных
    if [ -z "$interface" ] || [ -z "$gamefilter" ] || [ -z "$strategy" ]; then
        handle_error "Отсутствуют обязательные параметры в конфигурационном файле"
    fi
}

# Функция для настройки репозитория
setup_repository() {
    if [ -d "$REPO_DIR" ]; then
        log "Использование существующей версии репозитория."
        return
    else
        log "Клонирование репозитория..."
        git clone "$REPO_URL" "$REPO_DIR" || handle_error "Ошибка при клонировании репозитория"
        cd "$REPO_DIR" && git checkout $MAIN_REPO_REV && cd ..
        # rename_bat.sh
        chmod +x "$BASE_DIR/rename_bat.sh"
        rm -rf "$REPO_DIR/.git"
        "$BASE_DIR/rename_bat.sh" || handle_error "Ошибка при переименовании файлов"
    fi
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
    
    IFS=$'\n' bat_files=($(printf '%s\n' "${bat_files[@]}" | sort)); unset IFS

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
            
            # Удаляем --new в конце если есть
            # nfqws_args="${nfqws_args%% --new*}"
            
            # Очищаем лишние пробелы
            nfqws_args=$(echo "$match" | xargs)
            nfqws_args="${nfqws_args//=^!/=!}"
            
            nfqws_params+=("$nfqws_args")
            debug_log "Matched protocol: $protocol, ports: $ports"
            debug_log "NFQWS parameters: $nfqws_args"
        fi
    done < <(echo "$content" | grep -oP -- '--filter-(tcp|udp)=([0-9,-]+)\s+(?:[\s\S]*?--new|.*)')
}

# Обновленная функция настройки nftables с метками
setup_nftables() {
    local interface="$1"
    local table_inet="inet zapretunix"
    local table_ip="ip zapretunix"
    local common_chain="zapret_common"
    local rule_comment="Added by zapret script"
    local queue_num=220

    log "Настройка nftables (ROUTER_MODE=${ROUTER_MODE:-0})..."

    # Очистка только наших таблиц
    sudo nft delete table inet zapretunix 2>/dev/null
    sudo nft delete table ip zapretunix 2>/dev/null

    # ========== inet table ==========
    sudo nft add table inet zapretunix

    # Общая логическая цепочка
    sudo nft add chain $table_inet $common_chain

    # OUTPUT — всегда
    sudo nft add chain $table_inet output '{
        type filter hook output priority mangle;
        policy accept;
    }'
    sudo nft add rule $table_inet output jump $common_chain

    # FORWARD — только если router mode
    if [ "$ROUTER_MODE" = "1" ]; then
        sudo nft add chain $table_inet forward '{
            type filter hook forward priority mangle;
            policy accept;
        }'
        sudo nft add rule $table_inet forward jump $common_chain
    fi

    # Исключаем локальные сети
    sudo nft add rule $table_inet $common_chain \
        ip daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 255.255.255.255 } \
        return

    local oif_clause=""
    if [ -n "$interface" ] && [ "$interface" != "any" ]; then
        oif_clause="oifname \"$interface\""
    fi

    # TCP
    if [ -n "$tcp_ports" ]; then
        sudo nft add rule $table_inet $common_chain \
            $oif_clause meta mark != 0x40000000 \
            tcp dport { $tcp_ports } \
            counter queue num $queue_num bypass \
            comment \"$rule_comment\" \
        || handle_error "Ошибка при добавлении TCP правила nftables"
    fi

    # UDP
    if [ -n "$udp_ports" ]; then
        sudo nft add rule $table_inet $common_chain \
            $oif_clause meta mark != 0x40000000 \
            udp dport { $udp_ports } \
            counter queue num $queue_num bypass \
            comment \"$rule_comment\" \
        || handle_error "Ошибка при добавлении UDP правила nftables"
    fi

    # ========== NAT (только router mode) ==========
    if [ "$ROUTER_MODE" = "1" ]; then
        sudo nft add table ip zapretunix
        sudo nft add chain $table_ip postrouting '{
            type nat hook postrouting priority srcnat;
        }'
        sudo nft add rule $table_ip postrouting oifname "$interface" masquerade
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
    
    debug_log "Запуск nfqws с параметрами: $NFQWS_PATH --user=root --daemon --dpi-desync-fwmark=0x40000000 --qnum=220 $full_params"
    eval "sudo $NFQWS_PATH --user=root --daemon --dpi-desync-fwmark=0x40000000 --qnum=220 $full_params" ||
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
                load_config
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

# Запуск скрипта
main "$@"

trap _term SIGINT

sleep infinity &
wait
