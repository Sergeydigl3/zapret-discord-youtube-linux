#!/usr/bin/env bash

# Константы
BASE_DIR="$(realpath "$(dirname "$0")")"
REPO_DIR="$BASE_DIR/zapret-latest"
CUSTOM_DIR="./custom-strategies"
REPO_URL="https://github.com/Flowseal/zapret-discord-youtube"
NFQWS_PATH="$BASE_DIR/nfqws"
CONF_FILE="$BASE_DIR/conf.env"
STOP_SCRIPT="$BASE_DIR/stop_and_clean_nft.sh"

# Флаг отладки
DEBUG=false
NOINTERACTIVE=false


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
    if [ -z "$interface" ] || [ -z "$auto_update" ] || [ -z "$strategy" ]; then
        handle_error "Отсутствуют обязательные параметры в конфигурационном файле"
    fi
}

# Функция для настройки репозитория
setup_repository() {
    if [ -d "$REPO_DIR" ]; then
        if $NOINTERACTIVE && [ "$auto_update" != "true" ]; then
            log "Использование существующей версии репозитория."
            return
        fi
        
        read -p "Репозиторий уже существует. Обновить его? (y/n): " choice
        if [[ "$choice" =~ ^[Yy]$ ]] || $NOINTERACTIVE && [ "$auto_update" == "true" ]; then
            log "Обновление репозитория..."
            rm -rf "$REPO_DIR"
            git clone "$REPO_URL" "$REPO_DIR" || handle_error "Ошибка при клонировании репозитория"
            cd "$REPO_DIR" && git checkout 8a1885d7d06a098989c450bb851a9508d977725d && cd ..
            # rename_bat.sh
            chmod +x "$BASE_DIR/rename_bat.sh"
            rm -rf "$REPO_DIR/.git"
            "$BASE_DIR/rename_bat.sh" || handle_error "Ошибка при переименовании файлов"
        else
            log "Использование существующей версии репозитория."
        fi
    else
        log "Клонирование репозитория..."
        git clone "$REPO_URL" "$REPO_DIR" || handle_error "Ошибка при клонировании репозитория"
        cd "$REPO_DIR" && git checkout 8a1885d7d06a098989c450bb851a9508d977725d && cd ..
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
    local queue_num=0
    local bin_path="bin/"
    debug_log "Parsing .bat file: $file"
    
    while IFS= read -r line; do
        debug_log "Processing line: $line"
        
        [[ "$line" =~ ^[:space:]*:: || -z "$line" ]] && continue
        
        line="${line//%BIN%/$bin_path}"
        line="${line//%GameFilter/}"
        
        if [[ "$line" =~ --filter-(tcp|udp)=([0-9,-]+)[[:space:]](.*?)(--new|$) ]]; then
            local protocol="${BASH_REMATCH[1]}"
            local ports="${BASH_REMATCH[2]}"
            local nfqws_args="${BASH_REMATCH[3]}"
            
            # Replace %LISTS% with 'lists/' in nfqws_args
            nfqws_args="${nfqws_args//%LISTS%/lists/}"
            
            nft_rules+=("$protocol dport {$ports} counter queue num $queue_num bypass")
            nfqws_params+=("$nfqws_args")
            debug_log "Matched protocol: $protocol, ports: $ports, queue: $queue_num"
            debug_log "NFQWS parameters for queue $queue_num: $nfqws_args"
            
            ((queue_num++))
        fi
    done < <(grep -v "^@echo" "$file" | grep -v "^chcp" | tr -d '\r')
}

# Обновленная функция настройки nftables с метками
setup_nftables() {
    local interface="$1"
    local table_name="inet zapretunix"
    local chain_name="output"
    local rule_comment="Added by zapret script"
    
    log "Настройка nftables с очисткой только помеченных правил..."
    
    # Удаляем существующую таблицу, если она была создана этим скриптом
    if sudo nft list tables | grep -q "$table_name"; then
        sudo nft flush chain $table_name $chain_name
        sudo nft delete chain $table_name $chain_name
        sudo nft delete table $table_name
    fi
    
    # Добавляем таблицу и цепочку
    sudo nft add table $table_name
    sudo nft add chain $table_name $chain_name { type filter hook output priority 0\; }
    
    local oif_clause=""
    if [ -n "$interface" ] && [ "$interface" != "any" ]; then
        oif_clause="oifname \"$interface\""
    fi

    # Добавляем правила с пометкой
    for queue_num in "${!nft_rules[@]}"; do
        sudo nft add rule $table_name $chain_name $oif_clause ${nft_rules[$queue_num]} comment \"$rule_comment\" ||
        handle_error "Ошибка при добавлении правила nftables для очереди $queue_num"
    done
}

# Функция запуска nfqws
start_nfqws() {
    log "Запуск процессов nfqws..."
    sudo pkill -f nfqws
    cd "$REPO_DIR" || handle_error "Не удалось перейти в директорию $REPO_DIR"
    for queue_num in "${!nfqws_params[@]}"; do
        debug_log "Запуск nfqws с параметрами: $NFQWS_PATH --daemon --qnum=$queue_num ${nfqws_params[$queue_num]}"
        eval "sudo $NFQWS_PATH --daemon --qnum=$queue_num ${nfqws_params[$queue_num]}" ||
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
                load_config
                ;;
            *)
                break
                ;;
        esac
    done
    
    check_dependencies
    setup_repository
    
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
        echo ""
        read -p "Нажмите Enter для завершения..."
    fi
}

# Запуск скрипта
main "$@"

trap _term SIGINT

sleep infinity &
wait
