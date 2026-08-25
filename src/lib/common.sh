#!/usr/bin/env bash

# =============================================================================
# Общие функции для всех скриптов zapret-discord-youtube-linux
# =============================================================================

# Guard: проверяем что файл не был уже загружен
[[ -n "${_COMMON_SH_LOADED:-}" ]] && return 0
_COMMON_SH_LOADED=1

# Подключаем константы
source "$(dirname "${BASH_SOURCE[0]}")/constants.sh"

# Флаг отладки (можно переопределить в скрипте)
DEBUG=${DEBUG:-false}

# -----------------------------------------------------------------------------
# Логирование
# -----------------------------------------------------------------------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

debug_log() {
    if $DEBUG; then
        echo "[DEBUG] $1"
    fi
}

handle_error() {
    log "Ошибка: $1"
    exit 1
}

show_error() {
    echo -e "\e[31mОшибка: $1\e[0m"
    read -p "Нажмите Enter для продолжения..."
}

# -----------------------------------------------------------------------------
# Проверка зависимостей
# -----------------------------------------------------------------------------

check_dependencies() {
    export PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"
    local deps=("git" "grep" "sed" "curl")

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            handle_error "Не установлена утилита $dep"
        fi
    done

    # Проверяем наличие хотя бы одного бэкенда файрвола
    if ! command -v nft &>/dev/null && ! command -v iptables &>/dev/null; then
        handle_error "Не установлен nftables или iptables. Установите один из них."
    fi
}

# -----------------------------------------------------------------------------
# Работа с конфигурацией
# -----------------------------------------------------------------------------

# Проверка существования conf.env и обязательных полей
# Использование: if check_conf_file "$CONF_FILE"; then ...
check_conf_file() {
    local conf_file="${1:-$CONF_FILE}"

    if [[ ! -f "$conf_file" ]]; then
        return 1
    fi

    local required_fields=("interface" "gamefiltertcp" "gamefilterudp" "strategy")
    for field in "${required_fields[@]}"; do
        if ! grep -q "^${field}=[^[:space:]]" "$conf_file"; then
            return 1
        fi
    done

    # firewall_backend опционален — по умолчанию auto
    if ! grep -q "^firewall_backend=" "$conf_file"; then
        echo "firewall_backend=auto" >> "$conf_file"
    fi

    return 0
}

# Загрузка конфигурации из файла
load_config() {
    local conf_file="${1:-$CONF_FILE}"

    if [[ ! -f "$conf_file" ]]; then
        handle_error "Файл конфигурации $conf_file не найден"
    fi

    source "$conf_file"

    if [[ -z "$interface" ]] || [[ -z "$gamefiltertcp" ]] || [[ -z "$gamefilterudp" ]] || [[ -z "$strategy" ]]; then
        handle_error "Отсутствуют обязательные параметры в конфигурационном файле"
    fi

    # По умолчанию автоопределение бэкенда
    FIREWALL_BACKEND="${firewall_backend:-auto}"
}

# -----------------------------------------------------------------------------
# Управление nfqws
# -----------------------------------------------------------------------------

check_nfqws_status() {
    if pgrep -f "nfqws" >/dev/null; then
        echo "Демоны nfqws запущены."
    else
        echo "Демоны nfqws не запущены."
    fi
}

# Остановка всех процессов nfqws
stop_nfqws() {
    elevate pkill -f nfqws 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Работа со стратегиями
# -----------------------------------------------------------------------------

# Настройка репозитория со стратегиями
# Требует: REPO_DIR, REPO_URL, MAIN_REPO_REV, BASE_DIR, INTERACTIVE_MODE (опционально)
# Аргументы:
#   $1 - версия (коммит/тег/ветка), по умолчанию MAIN_REPO_REV
setup_repository() {
    local user_lists_dir="$BASE_DIR/user-lists"
    local version="${1:-$MAIN_REPO_REV}"

    if [ -d "$REPO_DIR" ]; then
        # В интерактивном режиме спрашиваем подтверждение
        if [[ "${INTERACTIVE_MODE:-false}" == "true" ]]; then
            log "Обнаружен существующий репозиторий стратегий."
            read -p "Удалить существующий репозиторий и загрузить заново? [y/N]: " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                log "Использование существующей версии репозитория."
                return 0
            fi
        fi

        # Сохраняем только пользовательские списки. Официальные list-*.txt / ipset-*.txt
        # должны прийти из новой версии, иначе download-deps заливает старый снимок.
        # *-user.txt уже живут в user-lists (часто хардлинк на lists/) — не копируем файл сам в себя.
        if [[ -d "$REPO_DIR/lists" ]]; then
            mkdir -p "$user_lists_dir"
            for f in ipset-exclude-user.txt list-general-user.txt list-exclude-user.txt; do
                if [[ -f "$REPO_DIR/lists/$f" && ! -e "$user_lists_dir/$f" ]]; then
                    cp -f "$REPO_DIR/lists/$f" "$user_lists_dir/$f"
                fi
            done
        fi
        log "Удаление существующего репозитория..."
        rm -rf "$REPO_DIR"
    fi

    log "Клонирование репозитория (версия: $version)..."

    # Проверяем, является ли версия хешем коммита (40 символов hex)
    if [[ "$version" =~ ^[0-9a-f]{40}$ ]]; then
        git clone "$REPO_URL" "$REPO_DIR" || \
            handle_error "Ошибка при клонировании репозитория"

        cd "$REPO_DIR" || handle_error "Не удалось перейти в директорию $REPO_DIR"
        git checkout "$version" || \
            handle_error "Ошибка при переключении на коммит '$version'. Проверьте, что коммит существует."
        cd - > /dev/null
    else
        git clone --branch "$version" --depth 1 "$REPO_URL" "$REPO_DIR" || \
            handle_error "Ошибка при клонировании репозитория. Проверьте, что версия '$version' существует."
    fi

    chmod +x "$BASE_DIR/src/rename_bat.sh"
    rm -rf "$REPO_DIR/.git"
    "$BASE_DIR/src/rename_bat.sh" || handle_error "Ошибка при переименовании файлов"

    if [[ -d "$REPO_DIR/lists" ]]; then
        local user_lists_dir="$BASE_DIR/user-lists"
        mkdir -p "$user_lists_dir"

        touch "$user_lists_dir/ipset-exclude-user.txt"
        touch "$user_lists_dir/list-general-user.txt"
        touch "$user_lists_dir/list-exclude-user.txt"

        chmod 644 "$user_lists_dir/ipset-exclude-user.txt"
        chmod 644 "$user_lists_dir/list-general-user.txt"
        chmod 644 "$user_lists_dir/list-exclude-user.txt"

        find "$user_lists_dir" -maxdepth 1 -type f ! -name '*-user.txt' -delete 2>/dev/null || true

        for file in "$user_lists_dir"/*-user.txt; do
            [[ -f "$file" ]] || continue
            ln -f "$file" "$REPO_DIR/lists/" 2>/dev/null || true
        done
    fi
}

ensure_config_exists() {
    if ! check_conf_file; then
        read -p "Конфигурация отсутствует или неполная. Создать конфигурацию сейчас? (y/n): " answer
        if [[ $answer =~ ^[Yy]$ ]]; then
            create_conf_file
        else
            echo "Операция отменена."
            read -p "Нажмите Enter для продолжения..."
            return 0
        fi
        if ! check_conf_file; then
            show_error "Файл конфигурации всё ещё некорректен. Операция отменена."
            return 0
        fi
    fi
    return 0
}

get_strategies() {
    {
        if [ -d "$CUSTOM_STRATEGIES_DIR" ]; then
            find "$CUSTOM_STRATEGIES_DIR" -maxdepth 1 -type f -name "*.bat" -printf "%f\n" 2>/dev/null
        fi
        if [ -d "$REPO_DIR" ]; then
            find "$REPO_DIR" -maxdepth 1 -type f \( -name "general*.bat" -o -name "discord*.bat" \) -printf "%f\n" 2>/dev/null
        fi
    } | sort -u
}

show_strategies() {
    echo "Доступные стратегии:"
    echo
    get_strategies
}

normalize_strategy() {
    local s="$1"
    local exact_match
    exact_match=$(get_strategies | grep -E "^(${s}|${s}\\.bat|general_${s}|general_${s}\\.bat)$" | head -n1)
    if [ -n "$exact_match" ]; then
        echo "$exact_match"
        return 0
    fi
    local case_insensitive_match
    case_insensitive_match=$(get_strategies | grep -i -E "^(${s}|${s}\\.bat|general_${s}|general_${s}\\.bat)$" | head -n1)
    if [ -n "$case_insensitive_match" ]; then
        echo "$case_insensitive_match"
        return 0
    fi
    return 1
}

select_strategy_interactive() {
    local strategies_list
    mapfile -t strategies_list < <(get_strategies)
    if [ ${#strategies_list[@]} -eq 0 ]; then
        handle_error "Не найдены файлы стратегий .bat"
    fi
    echo "Доступные стратегии:"
    select selected_strategy in "${strategies_list[@]}"; do
        if [ -n "$selected_strategy" ]; then
            log "Выбрана стратегия: $selected_strategy"
            return 0
        fi
        show_error "Неверный выбор. Попробуйте еще раз."
done
}

get_strategy_path() {
    local strategy="$1"
    if [ -f "$CUSTOM_STRATEGIES_DIR/$strategy" ]; then
        echo "$CUSTOM_STRATEGIES_DIR/$strategy"
    elif [ -f "$REPO_DIR/$strategy" ]; then
        echo "$REPO_DIR/$strategy"
    else
        echo ""
    fi
}

parse_bat_file() {
    local file="$1"
    local bin_path="bin/"
    debug_log "Parsing .bat file: $file"
    local content
    content=$(tr -d '\r' < "$file")
    debug_log "File content loaded"
    content="${content//%BIN%/$bin_path}"
    content="${content//%LISTS%/lists/}"
    if [ "${USE_GAME_FILTER_TCP:-false}" = true ]; then
        content="${content//%GameFilterTCP%/$GAME_FILTER_PORTS}"
    else
        content="${content//%GameFilterTCP%/$GAME_FILTER_OFF_PORTS}"
    fi
    if [ "${USE_GAME_FILTER_UDP:-false}" = true ]; then
        content="${content//%GameFilterUDP%/$GAME_FILTER_PORTS}"
    else
        content="${content//%GameFilterUDP%/$GAME_FILTER_OFF_PORTS}"
    fi
    if [ "${USE_GAME_FILTER:-false}" = true ]; then
        content="${content//%GameFilter%/$GAME_FILTER_PORTS}"
    else
        content="${content//%GameFilter%/$GAME_FILTER_OFF_PORTS}"
    fi
    local wf_tcp_count wf_udp_count
    wf_tcp_count=$(echo "$content" | grep -oP -- '--wf-tcp=' | wc -l)
    wf_udp_count=$(echo "$content" | grep -oP -- '--wf-udp=' | wc -l)
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
    tcp_ports=$(echo "$content" | grep -oP -- '--wf-tcp=\\K[0-9,-]+' | head -n1)
    udp_ports=$(echo "$content" | grep -oP -- '--wf-udp=\\K[0-9,-]+' | head -n1)
    debug_log "TCP ports: $tcp_ports"
    debug_log "UDP ports: $udp_ports"
    nfqws_params=()
    local match nfqws_args
    while IFS= read -r match; do
        [[ -z "$match" ]] && continue
        nfqws_args=$(printf '%s\n' "$match" | xargs)
        nfqws_args="${nfqws_args//=^!/=!}"
        nfqws_params+=("$nfqws_args")
        debug_log "NFQWS parameters: $nfqws_args"
    done < <(echo "$content" | grep -oP -- '--filter-(tcp|udp|l7)=\\S+\\s+(?:[\\s\\S]*?--new|.*)' || true)
    if [ ${#nfqws_params[@]} -eq 0 ]; then
        echo "ERROR: no --filter-tcp/--filter-udp/--filter-l7 instances in $file"
        exit 1
    fi
}

start_nfqws() {
    log "Запуск процесса nfqws..."
    stop_nfqws
    cd "$REPO_DIR" || handle_error "Не удалось перейти в директорию $REPO_DIR"
    local full_params=(
        "$NFQWS_PATH"
        --daemon
        --dpi-desync-fwmark="$NFT_MARK"
        --qnum="$NFT_QUEUE_NUM"
    )
    for params in "${nfqws_params[@]}"; do
        full_params+=($params)
    done
    debug_log "Запуск NFQWS с параметрами: ${full_params[@]}"
    elevate "${full_params[@]}" ||
        handle_error "Ошибка при запуске nfqws"
}

run_zapret() {
    stop_nfqws
    firewall_clear
    sleep 1
    if [ "$gamefiltertcp" == "true" -a "$gamefilterudp" == "true" ]; then
        USE_GAME_FILTER=true
        USE_GAME_FILTER_TCP=true
        USE_GAME_FILTER_UDP=true
        log "GameFilterTCP и GameFilterUDP включен"
    elif [ "$gamefiltertcp" == "true" ]; then
        USE_GAME_FILTER=true
        USE_GAME_FILTER_TCP=true
        USE_GAME_FILTER_UDP=false
        log "GameFilterTCP включен"
    elif [ "$gamefilterudp" == "true" ]; then
        USE_GAME_FILTER=true
        USE_GAME_FILTER_TCP=false
        USE_GAME_FILTER_UDP=true
        log "GameFilterUDP включен"
    else
        USE_GAME_FILTER=false
        USE_GAME_FILTER_TCP=false
        USE_GAME_FILTER_UDP=false
        log "GameFilter выключен"
    fi
    local strategy_path
    strategy_path=$(get_strategy_path "$strategy")
    if [ -z "$strategy_path" ]; then
        handle_error "Указанный .bat файл стратегии $strategy не найден"
    fi
    parse_bat_file "$strategy_path"
    local backend
    backend=$(detect_firewall_backend) || handle_error "Не удалось определить бэкенд файрвола"
    log "Настройка $backend..."
    firewall_setup "$tcp_ports" "$udp_ports" "$interface" ||
        handle_error "Ошибка при настройке $backend"
    start_nfqws
    log "Настройка успешно завершена"
}
