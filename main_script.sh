#!/usr/bin/env bash

set -eou pipefail

# Константы
BASE_DIR="$(realpath "$(dirname "$0")")"
REPO_DIR="$BASE_DIR/zapret-latest"
CUSTOM_DIR="./custom-strategies"
NFQWS_PATH="$BASE_DIR/nfqws"
CONF_FILE="$BASE_DIR/conf.env"
STOP_SCRIPT="$BASE_DIR/stop_and_clean.sh"

# Флаг отладки
DEBUG=false
NOINTERACTIVE=false

# GameFilter (будет загружено из conf.env)
GAME_FILTER_PORTS="1024-65535"
USE_GAME_FILTER=false

# Глобальные переменные для стратегий
declare -a nft_rules=()
declare -a nfqws_params=()

# Функция очистки при завершении скрипта
cleanup() {
    log "Получен сигнал завершения. Очистка..."
    sudo /usr/bin/env bash "$STOP_SCRIPT"
    exit 0
}

# Импортируем общие функции
source "$(dirname "$0")/utils/common.sh"

# Импортируем функции firewall
source "$(dirname "$0")/utils/firewall.sh"

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
    
    # Устанавливаем GameFilter флаг
    if [ "$gamefilter" == "true" ]; then
        USE_GAME_FILTER=true
        log "GameFilter включен"
    else
        USE_GAME_FILTER=false
        log "GameFilter выключен"
    fi
}

# Функция для парсинга стратегии из файла
parse_strategy_from_file() {
    local file="$1"
    local queue_num=0
    local bin_path="bin/"
    debug_log "Parsing strategy file: $file"
    
    while IFS= read -r line; do
        debug_log "Processing line: $line"
        
        [[ "$line" =~ ^[:space:]*:: || -z "$line" ]] && continue
        
        line="${line//%BIN%/$bin_path}"
        line="${line//%LISTS%/lists/}"
        
        # Обрабатываем GameFilter
        if [ "$USE_GAME_FILTER" = true ]; then
            # Заменяем %GameFilter% на порты
            line="${line//%GameFilter%/$GAME_FILTER_PORTS}"
        else
            # Удаляем GameFilter из списков портов
            line="${line//,%GameFilter%/}"
            line="${line//%GameFilter%,/}"
        fi
        
        if [[ "$line" =~ --filter-(tcp|udp)=([0-9,-]+)[[:space:]](.*?)(--new|$) ]]; then
            local protocol="${BASH_REMATCH[1]}"
            local ports="${BASH_REMATCH[2]}"
            local nfqws_args="${BASH_REMATCH[3]}"
            
            # Replace %LISTS% with 'lists/' in nfqws_args
            nfqws_args="${nfqws_args//%LISTS%/lists/}"
            nfqws_args="${nfqws_args//=^!/=!}"
            
            nft_rules+=("$protocol dport {$ports} counter queue num $queue_num bypass")
            nfqws_params+=("$nfqws_args")
            debug_log "Matched protocol: $protocol, ports: $ports, queue: $queue_num"
            debug_log "NFQWS parameters for queue $queue_num: $nfqws_args"
            
            ((queue_num++))
        fi
    done < <(grep -v "^@echo" "$file" | grep -v "^chcp" | tr -d '\r')
}

# Функция для загрузки стратегии
load_strategy() {
    local strategy="$1"
    
    # Определяем путь к файлу стратегии
    local strategy_file=""
    if [ -f "$REPO_DIR/$strategy" ]; then
        strategy_file="$REPO_DIR/$strategy"
    elif [ -f "$CUSTOM_DIR/$strategy" ]; then
        strategy_file="$CUSTOM_DIR/$strategy"
    else
        handle_error "Файл стратегии $strategy не найден в $REPO_DIR или $CUSTOM_DIR"
    fi
    
    log "Загрузка стратегии: $strategy"
    parse_strategy_from_file "$strategy_file"
}


setup_firewall() {
    local interface="$1"
    
    # Используем универсальную функцию настройки firewall
    setup_firewall_rules "$interface" "${nft_rules[@]}"
}

start_nfqws() {
    log "Запуск процессов nfqws..."
    sudo pkill -f nfqws
    cd "$REPO_DIR" || handle_error "Не удалось перейти в директорию $REPO_DIR"
    for queue_num in "${!nfqws_params[@]}"; do
        local args="${nfqws_params[$queue_num]}"
        debug_log "Запуск nfqws с параметрами: $NFQWS_PATH --daemon --qnum=$queue_num $args"
        
        # Разбиваем параметры на массив для безопасного выполнения
        IFS=' ' read -ra arg_array <<< "$args"
        sudo "$NFQWS_PATH" --daemon --qnum="$queue_num" "${arg_array[@]}" ||
        handle_error "Ошибка при запуске nfqws для очереди $queue_num"
    done
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
                ;;
            *)
                break
                ;;
        esac
    done
    
    # Проверяем что бинарный файл существует
    if [ ! -f "$NFQWS_PATH" ]; then
        handle_error "Бинарный файл nfqws не найден. Запустите сначала download_reqs.sh"
    fi
    
    # Проверяем что репозиторий со стратегиями существует
    if [ ! -d "$REPO_DIR" ]; then
        handle_error "Репозиторий со стратегиями не найден. Запустите сначала download_reqs.sh"
    fi
    
    check_dependencies
    
    # Загружаем конфигурацию
    if $NOINTERACTIVE; then
        load_config
    else
        # Интерактивный режим - загружаем конфиг или создаем новый
        if [ ! -f "$CONF_FILE" ]; then
            handle_error "Файл конфигурации $CONF_FILE не найден. Запустите download_reqs.sh --setup-strategy"
        fi
        load_config
    fi
    
    # Загружаем стратегию
    load_strategy "$strategy"
    
    # Настраиваем firewall
    setup_firewall "$interface"
    
    # Запускаем nfqws
    start_nfqws
    log "Настройка успешно завершена"
    
    # Пауза перед выходом
    if ! $NOINTERACTIVE; then
        echo "Нажмите Ctrl+C для завершения..."
    fi
}

# Запуск скрипта с правильной обработкой сигналов
main "$@"

# Установка обработчика сигналов после выполнения main
trap cleanup SIGINT SIGTERM

# Если скрипт запущен в интерактивном режиме, ждем сигнала завершения
if ! $NOINTERACTIVE; then
    log "Скрипт запущен. Нажмите Ctrl+C для завершения..."
    wait
fi
