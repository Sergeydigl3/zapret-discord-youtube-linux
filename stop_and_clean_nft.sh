#!/usr/bin/env bash

# Определяем BASE_DIR
BASE_DIR="$(realpath "$(dirname "$0")")"

# Подключаем общие библиотеки
source "$BASE_DIR/lib/constants.sh"
source "$BASE_DIR/lib/common.sh"

# Остановка процессов nfqws
stop_nfqws_processes() {
    log "Остановка всех процессов nfqws..."
    sudo pkill -f nfqws || log "Процессы nfqws не найдены"
}

# Очистка помеченных правил nftables
clear_firewall_rules() {
    log "Очистка правил nftables, добавленных скриптом..."

    # Проверка на существование таблицы и цепочки
    if sudo nft list tables | grep -q "$NFT_TABLE"; then
        if sudo nft list chain $NFT_TABLE $NFT_CHAIN >/dev/null 2>&1; then
            # Получаем все handle значений правил с меткой, добавленных скриптом
            handles=$(sudo nft -a list chain $NFT_TABLE $NFT_CHAIN | grep "$NFT_RULE_COMMENT" | awk '{print $NF}')

            # Удаление каждого правила по handle значению
            for handle in $handles; do
                sudo nft delete rule $NFT_TABLE $NFT_CHAIN handle $handle ||
                log "Не удалось удалить правило с handle $handle"
            done

            # Удаление цепочки и таблицы, если они пусты
            sudo nft delete chain $NFT_TABLE $NFT_CHAIN
            sudo nft delete table $NFT_TABLE

            log "Очистка завершена."
        else
            log "Цепочка $NFT_CHAIN не найдена в таблице $NFT_TABLE."
        fi
    else
        log "Таблица $NFT_TABLE не найдена. Нечего очищать."
    fi
}

# Основной процесс
stop_and_clear_firewall() {
    stop_nfqws_processes # Останавливаем процессы nfqws
    clear_firewall_rules # Чистим правила nftables
}

# Запуск
stop_and_clear_firewall
