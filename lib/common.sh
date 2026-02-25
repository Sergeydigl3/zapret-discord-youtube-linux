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

# -----------------------------------------------------------------------------
# Проверка зависимостей
# -----------------------------------------------------------------------------

check_dependencies() {
    local deps=("git" "nft" "grep" "sed")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            handle_error "Не установлена утилита $dep"
        fi
    done
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

    local required_fields=("interface" "gamefilter" "strategy")
    for field in "${required_fields[@]}"; do
        if ! grep -q "^${field}=[^[:space:]]" "$conf_file"; then
            return 1
        fi
    done
    return 0
}

# Загрузка конфигурации из файла
load_config() {
    local conf_file="${1:-$CONF_FILE}"

    if [[ ! -f "$conf_file" ]]; then
        handle_error "Файл конфигурации $conf_file не найден"
    fi

    source "$conf_file"

    if [[ -z "$interface" ]] || [[ -z "$gamefilter" ]] || [[ -z "$strategy" ]]; then
        handle_error "Отсутствуют обязательные параметры в конфигурационном файле"
    fi
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
    sudo pkill -f nfqws 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Работа со стратегиями
# -----------------------------------------------------------------------------

# Настройка репозитория со стратегиями
# Требует: REPO_DIR, REPO_URL, MAIN_REPO_REV, BASE_DIR, INTERACTIVE_MODE (опционально)
# Аргументы:
#   $1 - версия (коммит/тег/ветка), по умолчанию MAIN_REPO_REV
setup_repository() {
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

        log "Удаление существующего репозитория..."
        rm -rf "$REPO_DIR"
    fi

    log "Клонирование репозитория (версия: $version)..."

    # Проверяем, является ли версия хешем коммита (40 символов hex)
    if [[ "$version" =~ ^[0-9a-f]{40}$ ]]; then
        # Для хеша коммита клонируем весь репозиторий и делаем checkout
        git clone "$REPO_URL" "$REPO_DIR" || \
            handle_error "Ошибка при клонировании репозитория"

        cd "$REPO_DIR" || handle_error "Не удалось перейти в директорию $REPO_DIR"
        git checkout "$version" || \
            handle_error "Ошибка при переключении на коммит '$version'. Проверьте, что коммит существует."
        cd - > /dev/null
    else
        # Для тега или ветки используем shallow clone
        git clone --branch "$version" --depth 1 "$REPO_URL" "$REPO_DIR" || \
            handle_error "Ошибка при клонировании репозитория. Проверьте, что версия '$version' существует."
    fi

    chmod +x "$BASE_DIR/rename_bat.sh"
    rm -rf "$REPO_DIR/.git"
    "$BASE_DIR/rename_bat.sh" || handle_error "Ошибка при переименовании файлов"
}

# Проверка и создание конфига (helper для install_service и desktop)
ensure_config_exists() {
    if ! check_conf_file; then
        read -p "Конфигурация отсутствует или неполная. Создать конфигурацию сейчас? (y/n): " answer
        if [[ $answer =~ ^[Yy]$ ]]; then
            create_conf_file
        else
            echo "Операция отменена."
            return 1
        fi
        # Перепроверяем конфигурацию
        if ! check_conf_file; then
            echo "Файл конфигурации всё ещё некорректен. Операция отменена."
            return 1
        fi
    fi
    return 0
}

# Получение списка доступных стратегий (имена файлов)
# Требует: REPO_DIR, CUSTOM_STRATEGIES_DIR
get_strategies() {
    {
        # Кастомные стратегии
        if [ -d "$CUSTOM_STRATEGIES_DIR" ]; then
            find "$CUSTOM_STRATEGIES_DIR" -maxdepth 1 -type f -name "*.bat" -printf "%f\n" 2>/dev/null
        fi
        # Стратегии из репозитория
        if [ -d "$REPO_DIR" ]; then
            find "$REPO_DIR" -maxdepth 1 -type f \( -name "general*.bat" -o -name "discord*.bat" \) -printf "%f\n" 2>/dev/null
        fi
    } | sort -u
}

# Вывод списка стратегий
show_strategies() {
    echo "Доступные стратегии:"
    echo
    get_strategies
}

# Валидация и нормализация названия стратегии
# Возвращает 0 и выводит нормализованное имя, или 1 при ошибке
normalize_strategy() {
    local s="$1"

    # Поиск точного совпадения
    local exact_match
    exact_match=$(get_strategies | grep -E "^(${s}|${s}\\.bat|general_${s}|general_${s}\\.bat)$" | head -n1)

    if [ -n "$exact_match" ]; then
        echo "$exact_match"
        return 0
    fi

    # Регистронезависимый поиск
    local case_insensitive_match
    case_insensitive_match=$(get_strategies | grep -i -E "^(${s}|${s}\\.bat|general_${s}|general_${s}\\.bat)$" | head -n1)

    if [ -n "$case_insensitive_match" ]; then
        echo "$case_insensitive_match"
        return 0
    fi

    return 1
}

# Интерактивный выбор стратегии
# Записывает результат в переменную $selected_strategy
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
        echo "Неверный выбор. Попробуйте еще раз."
    done
}

# Получение полного пути к файлу стратегии
# Возвращает путь к файлу или пустую строку если не найден
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

# -----------------------------------------------------------------------------
# Парсинг .bat файлов стратегий
# -----------------------------------------------------------------------------

# Парсинг параметров из bat файла
# Устанавливает глобальные переменные: tcp_ports, udp_ports, nfqws_params[]
# Требует: USE_GAME_FILTER, GAME_FILTER_PORTS
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
    nfqws_params=()
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

# -----------------------------------------------------------------------------
# Запуск nfqws
# -----------------------------------------------------------------------------

# Запуск процесса nfqws
# Требует: NFQWS_PATH, REPO_DIR, NFT_MARK, NFT_QUEUE_NUM, nfqws_params[]
start_nfqws() {
    log "Запуск процесса nfqws..."
    stop_nfqws
    cd "$REPO_DIR" || handle_error "Не удалось перейти в директорию $REPO_DIR"

    local full_params=""
    for params in "${nfqws_params[@]}"; do
        full_params="$full_params $params"
    done

    debug_log "Запуск nfqws с параметрами: $NFQWS_PATH --daemon --dpi-desync-fwmark=$NFT_MARK --qnum=$NFT_QUEUE_NUM $full_params"
    eval "sudo $NFQWS_PATH --daemon --dpi-desync-fwmark=$NFT_MARK --qnum=$NFT_QUEUE_NUM $full_params" ||
        handle_error "Ошибка при запуске nfqws"
}

# -----------------------------------------------------------------------------
# Основная функция запуска zapret
# -----------------------------------------------------------------------------

# Запуск zapret с указанной конфигурацией
# Использует глобальные переменные из conf.env: interface, gamefilter, strategy
# Требует: REPO_DIR, NFQWS_PATH, STOP_SCRIPT
run_zapret() {
    # Остановка предыдущего экземпляра
    source "$BASE_DIR/lib/firewall.sh"
    stop_nfqws
    nft_clear
    sleep 1

    # Установка USE_GAME_FILTER
    if [ "$gamefilter" == "true" ]; then
        USE_GAME_FILTER=true
        log "GameFilter включен"
    else
        USE_GAME_FILTER=false
        log "GameFilter выключен"
    fi

    # Получаем путь к стратегии
    local strategy_path
    strategy_path=$(get_strategy_path "$strategy")
    if [ -z "$strategy_path" ]; then
        handle_error "Указанный .bat файл стратегии $strategy не найден"
    fi

    # Парсим стратегию
    parse_bat_file "$strategy_path"

    # Настройка nftables
    log "Настройка nftables..."
    nft_setup "$tcp_ports" "$udp_ports" "$interface" ||
        handle_error "Ошибка при настройке nftables"
    log "Настройка nftables завершена (TCP: $tcp_ports, UDP: $udp_ports)"

    # Запуск nfqws
    start_nfqws
    log "Настройка успешно завершена"
}
