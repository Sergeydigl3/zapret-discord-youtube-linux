#!/usr/bin/env bash

# =============================================================================
# Управление повышением привилегий (sudo/doas)
# =============================================================================

# Кэш для выбранного инструмента
_ELEVATE_CMD=""

# Определяет доступный инструмент для повышения привилегий
# Возвращает: sudo, doas или пустую строку если уже root
_detect_elevate_cmd() {
    # Если уже root — ничего не нужно
    if [[ $EUID -eq 0 ]]; then
        echo ""
        return 0
    fi

    # Проверяем doas (предпочтительнее на некоторых системах)
    if command -v doas >/dev/null 2>&1; then
        # Проверяем, что doas настроен для текущего пользователя
        if doas -n true 2>/dev/null; then
            echo "doas"
            return 0
        fi
    fi

    # Проверяем sudo
    if command -v sudo >/dev/null 2>&1; then
        echo "sudo"
        return 0
    fi

    # Ничего не найдено
    return 1
}

# Получает команду для повышения привилегий (с кэшированием)
get_elevate_cmd() {
    if [[ -z "$_ELEVATE_CMD" ]]; then
        _ELEVATE_CMD=$(_detect_elevate_cmd) || {
            echo "Ошибка: не найден sudo или doas для повышения привилегий" >&2
            return 1
        }
    fi
    echo "$_ELEVATE_CMD"
}

# Выполняет команду с повышенными привилегиями
# Использование: elevate команда аргументы...
elevate() {
    local cmd
    cmd=$(get_elevate_cmd) || return 1

    if [[ -n "$cmd" ]]; then
        "$cmd" "$@"
    else
        # Уже root — выполняем напрямую
        "$@"
    fi
}

# Проверяет, доступно ли повышение привилегий
check_elevate_available() {
    get_elevate_cmd >/dev/null 2>&1
}

# Проверяет, выполняется ли скрипт от root
is_root() {
    [[ $EUID -eq 0 ]]
}

# Запрашивает повышение привилегий заранее (кэширует пароль)
# Полезно вызвать перед длительными операциями
elevate_cache_credentials() {
    local cmd
    cmd=$(get_elevate_cmd) || return 1

    if [[ -n "$cmd" ]]; then
        # Для sudo: обновляем timestamp
        if [[ "$cmd" == "sudo" ]]; then
            sudo -v
        fi
        # doas обычно не требует предварительного кэширования
    fi
}
