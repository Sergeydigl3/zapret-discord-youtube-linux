#!/usr/bin/env bash

# =============================================================================
# Загрузчик бэкендов файрвола
# =============================================================================
# Добавление нового бэкенда:
#   1. Создать src/firewall-backends/<name>.sh
#   2. Определить три функции: backend_check, backend_setup, backend_clear
#   3. Всё — авто-детект подберёт файл сам
# =============================================================================

[[ -n "${_FIREWALL_SH_LOADED:-}" ]] && return 0
_FIREWALL_SH_LOADED=1

if [[ -z "$NFT_TABLE" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/constants.sh"
fi

_BACKENDS_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")/../firewall-backends")"
_LOADED_BACKEND=""

# -----------------------------------------------------------------------------
# _find_backend_file — найти файл бэкенда по каноническому имени
# -----------------------------------------------------------------------------
# Ищет среди файлов вида <префикс-имя>.sh, возвращает полный путь.
# Префикс — две цифры + тире (00-, 01-). Без префикса тоже работает.
# Пример: _find_backend_file "nftables" → ".../00-nftables.sh"
# -----------------------------------------------------------------------------
_find_backend_file() {
    local name="$1"
    for f in "$_BACKENDS_DIR"/*.sh; do
        [[ -f "$f" ]] || continue
        local base clean
        base=$(basename "$f" .sh)
        clean="$base"
        [[ "$base" =~ ^[0-9][0-9]-(.*) ]] && clean="${BASH_REMATCH[1]}"
        if [[ "$clean" == "$name" ]]; then
            echo "$f"
            return 0
        fi
    done
    return 1
}

# -----------------------------------------------------------------------------
# _canonical_name — получить каноническое имя из имени файла
# -----------------------------------------------------------------------------
# Пример: "00-nftables" → "nftables", "nftables" → "nftables"
# -----------------------------------------------------------------------------
_canonical_name() {
    local base="$1"
    if [[ "$base" =~ ^[0-9][0-9]-(.*) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "$base"
    fi
}

# -----------------------------------------------------------------------------
# detect_firewall_backend — определяет, какой бэкенд использовать
# -----------------------------------------------------------------------------
# Авто-детект: перебирает все .sh в _BACKENDS_DIR, проверяет backend_check().
# Порядок = алфавитный по имени файла (00-nftables > 01-iptables).
# Можно принудительно указать FIREWALL_BACKEND=<name>.
# -----------------------------------------------------------------------------
detect_firewall_backend() {
    local backend="${FIREWALL_BACKEND:-auto}"

    if [[ "$backend" != "auto" ]]; then
        if ! _find_backend_file "$backend" >/dev/null; then
            handle_error "Бэкенд '$backend' не найден в $_BACKENDS_DIR"
        fi
        echo "$backend"
        return 0
    fi

    for module in "$_BACKENDS_DIR"/*.sh; do
        [[ -f "$module" ]] || continue
        local name
        name=$(_canonical_name "$(basename "$module" .sh)")
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

    local module
    module=$(_find_backend_file "$backend") || {
        handle_error "Модуль бэкенда не найден: $backend"
    }

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

# -----------------------------------------------------------------------------
# list_available_backends — вывести список доступных бэкендов (канонические имена)
# -----------------------------------------------------------------------------
list_available_backends() {
    for f in "$_BACKENDS_DIR"/*.sh; do
        [[ -f "$f" ]] || continue
        local base
        base=$(basename "$f" .sh)
        _canonical_name "$base"
    done
}
