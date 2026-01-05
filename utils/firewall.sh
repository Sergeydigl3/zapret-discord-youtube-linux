#!/usr/bin/env bash

# Основной интерфейс для работы с firewall
# Автоматически определяет и использует nftables или iptables

# Импортируем общие функции
source "$(dirname "$0")/utils/common.sh"

# Константы для nftables
NFT_TABLE_NAME="inet zapretunix"
NFT_CHAIN_NAME="output"
NFT_RULE_COMMENT="Added by zapret script"

# Константы для iptables
IPT_CHAIN_NAME="ZAPRET_UNIX"

# Функция для определения доступного firewall
get_firewall_type() {
    detect_firewall
}

# Функция очистки правил firewall
clear_firewall_rules() {
    local firewall=$(get_firewall_type)
    
    case "$firewall" in
        "nftables")
            source "$(dirname "$0")/utils/firewalls/nftables.sh"
            clear_nftables_rules
            ;;
        "iptables")
            source "$(dirname "$0")/utils/firewalls/iptables.sh"
            clear_iptables_rules
            ;;
        "none")
            log "Не найден nftables или iptables"
            ;;
    esac
}

# Функция настройки firewall
setup_firewall_rules() {
    local interface="$1"
    local rules=("${@:2}")  # Все остальные аргументы - это правила
    
    local firewall=$(get_firewall_type)
    
    case "$firewall" in
        "nftables")
            source "$(dirname "$0")/firewalls/nftables.sh"
            setup_nftables_rules "$interface" "${rules[@]}"
            ;;
        "iptables")
            source "$(dirname "$0")/firewalls/iptables.sh"
            setup_iptables_rules "$interface" "${rules[@]}"
            ;;
        "none")
            handle_error "Не найден nftables или iptables"
            ;;
    esac
}

# Функция для получения текущего состояния firewall
get_firewall_status() {
    local firewall=$(get_firewall_type)
    
    case "$firewall" in
        "nftables")
            source "$(dirname "$0")/firewalls/nftables.sh"
            get_nftables_status
            ;;
        "iptables")
            source "$(dirname "$0")/firewalls/iptables.sh"
            get_iptables_status
            ;;
        "none")
            echo "Firewall не обнаружен"
            ;;
    esac
}