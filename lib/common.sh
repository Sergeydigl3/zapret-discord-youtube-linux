#!/usr/bin/env bash

# =============================================================================
# Общие функции для всех скриптов zapret-discord-youtube-linux
# =============================================================================

# Подключаем константы если ещё не подключены
if [[ -z "$SERVICE_NAME" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/constants.sh"
fi

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
# Проверка статуса nfqws
# -----------------------------------------------------------------------------

check_nfqws_status() {
    if pgrep -f "nfqws" >/dev/null; then
        echo "Демоны nfqws запущены."
    else
        echo "Демоны nfqws не запущены."
    fi
}
