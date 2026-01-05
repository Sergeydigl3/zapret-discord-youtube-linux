#!/usr/bin/env bash

set -eou pipefail

# Универсальный скрипт очистки firewall и остановки процессов
# Поддерживает nftables и iptables


# Импортируем функции firewall
source "$(dirname "$0")/utils/firewall.sh"

# Основной процесс
stop_and_clear_firewall() {
    stop_nfqws_processes
    
    clear_firewall_rules
}

# Запуск
stop_and_clear_firewall