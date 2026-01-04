#!/usr/bin/env bash

# Универсальный скрипт очистки firewall и остановки процессов
# Поддерживает nftables и iptables

# Импортируем общие функции
source "$(dirname "$0")/utils/common.sh"

# Константы для nftables
NFT_TABLE_NAME="inet zapretunix"
NFT_CHAIN_NAME="output"
NFT_RULE_COMMENT="Added by zapret script"

# Константы для iptables
IPT_CHAIN_NAME="ZAPRET_UNIX"

# Очистка правил nftables
clear_nftables_rules() {
    log "Очистка правил nftables, добавленных скриптом..."
    
    # Проверка на существование таблицы и цепочки
    if sudo nft list tables | grep -q "$NFT_TABLE_NAME"; then
        if sudo nft list chain $NFT_TABLE_NAME $NFT_CHAIN_NAME >/dev/null 2>&1; then
            # Получаем все handle значений правил с меткой, добавленных скриптом
            handles=$(sudo nft -a list chain $NFT_TABLE_NAME $NFT_CHAIN_NAME | grep "$NFT_RULE_COMMENT" | awk '{print $NF}')
            
            # Удаление каждого правила по handle значению
            for handle in $handles; do
                sudo nft delete rule $NFT_TABLE_NAME $NFT_CHAIN_NAME handle $handle ||
                log "Не удалось удалить правило с handle $handle"
            done
            
            # Удаление цепочки и таблицы, если они пусты
            sudo nft delete chain $NFT_TABLE_NAME $NFT_CHAIN_NAME 2>/dev/null || true
            sudo nft delete table $NFT_TABLE_NAME 2>/dev/null || true
            
            log "Очистка nftables завершена."
        else
            log "Цепочка $NFT_CHAIN_NAME не найдена в таблице $NFT_TABLE_NAME."
        fi
    else
        log "Таблица $NFT_TABLE_NAME не найдена. Нечего очищать."
    fi
}

# Очистка правил iptables
clear_iptables_rules() {
    log "Очистка правил iptables, добавленных скриптом..."
    
    # Проверка существования цепочки
    if sudo iptables -L "$IPT_CHAIN_NAME" -n >/dev/null 2>&1; then
        # Удаляем правила из OUTPUT, которые ссылаются на нашу цепочку
        sudo iptables -D OUTPUT -j "$IPT_CHAIN_NAME" 2>/dev/null || true
        
        # Очищаем и удаляем нашу цепочку
        sudo iptables -F "$IPT_CHAIN_NAME" 2>/dev/null || true
        sudo iptables -X "$IPT_CHAIN_NAME" 2>/dev/null || true
        
        log "Очистка iptables завершена."
    else
        log "Цепочка $IPT_CHAIN_NAME не найдена. Нечего очищать."
    fi
}

# Основной процесс
stop_and_clear_firewall() {
    stop_nfqws_processes
    
    local firewall=$(detect_firewall)
    
    case "$firewall" in
        "nftables")
            clear_nftables_rules
            ;;
        "iptables")
            clear_iptables_rules
            ;;
        "none")
            log "Не найден nftables или iptables"
            ;;
    esac
}

# Запуск
stop_and_clear_firewall