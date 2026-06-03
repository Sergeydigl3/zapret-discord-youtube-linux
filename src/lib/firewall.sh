#!/usr/bin/env bash

# =============================================================================
# Загрузчик бэкендов файрвола
# =============================================================================
# Добавление нового бэкенда:
#   1. Создать src/firewall-backends/<name>.sh
#   2. Определить три функции: backend_check, backend_setup, backend_clear
#   3. Всё — авто-детект подберёт файл сам
# =============================================================================

if [[ -z "$NFT_TABLE" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/constants.sh"
fi

_BACKENDS_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")/../firewall-backends")"
_LOADED_BACKEND=""

# -----------------------------------------------------------------------------
# detect_firewall_backend — определяет, какой бэкенд использовать
# -----------------------------------------------------------------------------
# Авто-детект: перебирает все .sh в _BACKENDS_DIR, проверяет backend_check().
# Порядок = алфавитный (nftables > iptables из-за имени файла).
# Можно принудительно указать FIREWALL_BACKEND=<name>.
# -----------------------------------------------------------------------------
detect_firewall_backend() {
    local backend="${FIREWALL_BACKEND:-auto}"

    if [[ "$backend" != "auto" ]]; then
        if [[ ! -f "$_BACKENDS_DIR/${backend}.sh" ]]; then
            handle_error "Бэкенд '$backend' не найден в $_BACKENDS_DIR"
        fi
        echo "$backend"
        return 0
    fi

    for module in "$_BACKENDS_DIR"/*.sh; do
        [[ -f "$module" ]] || continue
        local name
        name=$(basename "$module" .sh)
        if (
            source "$module" >/dev/null 2>&1
            backend_check >/dev/null 2>&1
        ); then
            echo "$name"
            return 0
        fi
    done

    handle_error "Не найден ни один доступный бэкенд файрвола"
}

# -----------------------------------------------------------------------------
# load_firewall_backend — загружает модуль бэкенда
# -----------------------------------------------------------------------------
load_firewall_backend() {
    local backend
    backend=$(detect_firewall_backend)

    local module="$_BACKENDS_DIR/${backend}.sh"
    if [[ ! -f "$module" ]]; then
        handle_error "Модуль бэкенда не найден: $module"
    fi

    source "$module"

    if ! backend_check; then
        handle_error "Бэкенд $backend недоступен (не установлены необходимые утилиты)"
    fi

    _LOADED_BACKEND="$backend"
    log "Загружен бэкенд файрвола: $backend"
}

# -----------------------------------------------------------------------------
# firewall_setup — создаёт правила через загруженный бэкенд
# -----------------------------------------------------------------------------
firewall_setup() {
    [[ -z "$_LOADED_BACKEND" ]] && load_firewall_backend
    backend_setup "$@" || handle_error "Ошибка при настройке $_LOADED_BACKEND"
    log "Настройка $_LOADED_BACKEND завершена (TCP: ${1:-—}, UDP: ${2:-—})"
}

# -----------------------------------------------------------------------------
# firewall_clear — удаляет правила через загруженный бэкенд
# -----------------------------------------------------------------------------
firewall_clear() {
    [[ -z "$_LOADED_BACKEND" ]] && load_firewall_backend
    backend_clear
    log "Очистка $_LOADED_BACKEND завершена"
}
