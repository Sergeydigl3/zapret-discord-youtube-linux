#!/usr/bin/env bash

# Функции для работы с nftables

# Импортируем общие функции
source "$(dirname "$0")/utils/common.sh"

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

# Настройка правил nftables
setup_nftables_rules() {
    local interface="$1"
    shift
    local rules=("$@")
    
    log "Настройка nftables с очисткой только помеченных правил..."
    
    # Удаляем существующую таблицу, если она была создана этим скриптом
    if sudo nft list tables | grep -q "$NFT_TABLE_NAME"; then
        sudo nft flush chain $NFT_TABLE_NAME $NFT_CHAIN_NAME
        sudo nft delete chain $NFT_TABLE_NAME $NFT_CHAIN_NAME
        sudo nft delete table $NFT_TABLE_NAME
    fi
    
    # Добавляем таблицу и цепочку
    sudo nft add table $NFT_TABLE_NAME
    sudo nft add chain $NFT_TABLE_NAME $NFT_CHAIN_NAME { type filter hook output priority 0\; }
    
    local oif_clause=""
    if [ -n "$interface" ] && [ "$interface" != "any" ]; then
        oif_clause="oifname \"$interface\""
    fi
    
    # Добавляем правила с пометкой
    for rule in "${rules[@]}"; do
        sudo nft add rule $NFT_TABLE_NAME $NFT_CHAIN_NAME $oif_clause $rule comment "$NFT_RULE_COMMENT" ||
        handle_error "Ошибка при добавлении правила nftables: $rule"
    done
}

# Получение статуса nftables
get_nftables_status() {
    if sudo nft list tables | grep -q "$NFT_TABLE_NAME"; then
        echo "nftables: таблица $NFT_TABLE_NAME существует"
        if sudo nft list chain $NFT_TABLE_NAME $NFT_CHAIN_NAME >/dev/null 2>&1; then
            echo "nftables: цепочка $NFT_CHAIN_NAME существует"
            local rule_count=$(sudo nft list chain $NFT_TABLE_NAME $NFT_CHAIN_NAME | grep "$NFT_RULE_COMMENT" | wc -l)
            echo "nftables: активных правил: $rule_count"
        else
            echo "nftables: цепочка $NFT_CHAIN_NAME не найдена"
        fi
    else
        echo "nftables: таблица $NFT_TABLE_NAME не найдена"
    fi
}