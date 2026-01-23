#!/usr/bin/env bash

# ===== Константы =====
INET_TABLE="inet zapretunix"
IP_TABLE="ip zapretunix"

# ===== Логирование =====
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# ===== Остановка nfqws =====
stop_nfqws_processes() {
    log "Остановка процессов nfqws..."
    sudo pkill -f nfqws || log "Процессы nfqws не найдены"
}

# ===== Очистка nftables =====
clear_firewall_rules() {
    log "Очистка nftables (zapretunix)..."

    # inet table — всегда
    if sudo nft list table inet zapretunix >/dev/null 2>&1; then
        sudo nft delete table inet zapretunix \
            && log "Удалена таблица inet zapretunix" \
            || log "Ошибка при удалении inet zapretunix"
    else
        log "Таблица inet zapretunix не найдена"
    fi

    # ip table — только если был router mode
    if sudo nft list table ip zapretunix >/dev/null 2>&1; then
        sudo nft delete table ip zapretunix \
            && log "Удалена таблица ip zapretunix" \
            || log "Ошибка при удалении ip zapretunix"
    else
        log "Таблица ip zapretunix не найдена"
    fi

    log "Очистка nftables завершена"
}

# ===== Основной процесс =====
stop_and_clear_firewall() {
    stop_nfqws_processes
    clear_firewall_rules
}

# ===== Запуск =====
stop_and_clear_firewall
