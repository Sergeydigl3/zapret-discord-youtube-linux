#!/bin/bash

# Константы
TABLE_NAME="inet zapretunix"
CHAIN_NAME="output"
RULE_COMMENT="Added by zapret script"

# Функция для логирования
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Остановка процессов nfqws
stop_nfqws_processes() {
    log "Остановка всех процессов nfqws..."
    sudo pkill -f nfqws || log "Процессы nfqws не найдены"
}

# Очистка помеченных правил nftables
clear_firewall_rules() {
    log "Очистка правил nftables, добавленных скриптом..."
    
    # Проверка на существование таблицы и цепочки
    if sudo nft list tables | grep -q "$TABLE_NAME"; then
        if sudo nft list chain $TABLE_NAME $CHAIN_NAME >/dev/null 2>&1; then
            # Получаем все handle значений правил с меткой, добавленных скриптом
            handles=$(sudo nft -a list chain $TABLE_NAME $CHAIN_NAME | grep "$RULE_COMMENT" | awk '{print $NF}')
            
            # Удаление каждого правила по handle значению
            for handle in $handles; do
                sudo nft delete rule $TABLE_NAME $CHAIN_NAME handle $handle ||
                log "Не удалось удалить правило с handle $handle"
            done
            
            # Удаление цепочки и таблицы, если они пусты
            sudo nft delete chain $TABLE_NAME $CHAIN_NAME
            sudo nft delete table $TABLE_NAME
            
            log "Очистка завершена."
        else
            log "Цепочка $CHAIN_NAME не найдена в таблице $TABLE_NAME."
        fi
    else
        log "Таблица $TABLE_NAME не найдена. Нечего очищать."
    fi
}

# Основной процесс
stop_and_clear_firewall() {
    stop_nfqws_processes # Останавливаем процессы nfqws
    clear_firewall_rules # Чистим правила nftables
}

# Запуск
stop_and_clear_firewall
