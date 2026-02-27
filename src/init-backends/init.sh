#!/usr/bin/env bash

# =============================================================================
# Определение системы инициализации и подключение соответствующего backend
# При подключении (source) автоматически определяет систему и загружает backend
# =============================================================================

# Директория с backend-скриптами (абсолютный путь)
_INIT_BACKENDS_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"

# -----------------------------------------------------------------------------
# detect_init_system - определяет систему инициализации
# -----------------------------------------------------------------------------
detect_init_system() {
    local comm exe exe_name

    # Пробуем без elevate, если не получится — с elevate
    comm=$(cat /proc/1/comm 2>/dev/null | tr -d '\n')
    exe=$(readlink -f /proc/1/exe 2>/dev/null)

    # Если не удалось прочитать — пробуем с elevate
    if [[ -z "$comm" ]]; then
        comm=$(elevate cat /proc/1/comm 2>/dev/null | tr -d '\n')
    fi
    if [[ -z "$exe" ]]; then
        exe=$(elevate readlink -f /proc/1/exe 2>/dev/null)
    fi

    exe_name=$(basename "$exe" 2>/dev/null)

    # SYSTEMD
    if [[ "$exe_name" == "systemd" ]] || [[ -d "/run/systemd/system" ]]; then
        echo "systemd"
        return
    fi

    # DINIT
    if [[ "$exe_name" == "dinit" ]] || [[ "$comm" == "dinit" ]]; then
        echo "dinit"
        return
    fi

    # RUNIT
    if [[ "$exe_name" == runit* ]]; then
        echo "runit"
        return
    fi

    # S6
    if [[ "$exe_name" == s6-svscan* ]] || [[ -d "/run/s6" ]] || [[ -d "/var/run/s6" ]]; then
        echo "s6"
        return
    fi

    # OPENRC
    if [[ -d "/run/openrc" ]] || [[ -f "/sbin/rc" ]] || [[ -f "/etc/init.d/rc" ]] || type rc-status >/dev/null 2>&1; then
        echo "openrc"
        return
    fi

    # SYSVINIT
    if [[ "$exe_name" == "init" ]] || [[ "$comm" == "init" ]]; then
        echo "sysvinit"
        return
    fi

    echo "unknown/container ($exe_name)"
    return 1
}

# -----------------------------------------------------------------------------
# Автоматическое определение и подключение backend при source
# -----------------------------------------------------------------------------
INIT_SYS=$(detect_init_system) || {
    echo "Ошибка: Неизвестная система инициализации: $INIT_SYS"
    exit 1
}

_INIT_BACKEND_SCRIPT="${_INIT_BACKENDS_DIR}/${INIT_SYS}.sh"

if [[ -f "$_INIT_BACKEND_SCRIPT" ]]; then
    echo "Обнаружена система: $INIT_SYS"
    source "$_INIT_BACKEND_SCRIPT"
else
    echo "Ошибка: Не найден скрипт для системы $INIT_SYS ($_INIT_BACKEND_SCRIPT)"
    exit 1
fi

unset _INIT_BACKENDS_DIR _INIT_BACKEND_SCRIPT
