#!/usr/bin/env bash

# Определяем BASE_DIR
BASE_DIR="$(realpath "$(dirname "$0")")"

# Подключаем библиотеки
source "$BASE_DIR/lib/constants.sh"
source "$BASE_DIR/lib/common.sh"
source "$BASE_DIR/lib/firewall.sh"

# Основной процесс
stop_and_clear_firewall() {
    log "Остановка nfqws..."
    stop_nfqws
    log "Очистка правил nftables..."
    nft_clear
    log "Очистка завершена."
}

# Запуск
stop_and_clear_firewall
