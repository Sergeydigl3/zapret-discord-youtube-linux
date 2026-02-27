#!/usr/bin/env bash

# =============================================================================
# Функции для работы с nftables
# =============================================================================

# Подключаем константы если ещё не подключены
if [[ -z "$NFT_TABLE" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/constants.sh"
fi

# Проверяем наличие nftables
if ! command -v nft >/dev/null 2>&1; then
    echo "Ошибка: nftables не установлен. Установите пакет nftables."
    exit 1
fi

# -----------------------------------------------------------------------------
# nft_setup - создаёт таблицу, цепочку и правила nftables
# -----------------------------------------------------------------------------
# Аргументы:
#   $1 - tcp_ports   (например: "80,443" или "")
#   $2 - udp_ports   (например: "443,50000-50100" или "")
#   $3 - interface   (например: "eth0" или "any" или "")
#   $4 - table       (опционально, по умолчанию $NFT_TABLE)
#   $5 - chain       (опционально, по умолчанию $NFT_CHAIN)
#   $6 - queue_num   (опционально, по умолчанию $NFT_QUEUE_NUM)
#   $7 - mark        (опционально, по умолчанию $NFT_MARK)
#   $8 - comment     (опционально, по умолчанию $NFT_RULE_COMMENT)
# -----------------------------------------------------------------------------
nft_setup() {
    local tcp_ports="${1:-}"
    local udp_ports="${2:-}"
    local interface="${3:-}"
    local table="${4:-$NFT_TABLE}"
    local chain="${5:-$NFT_CHAIN}"
    local queue_num="${6:-$NFT_QUEUE_NUM}"
    local mark="${7:-$NFT_MARK}"
    local comment="${8:-$NFT_RULE_COMMENT}"

    local oif_clause=""
    if [[ -n "$interface" && "$interface" != "any" ]]; then
        oif_clause="oifname \"$interface\""
    fi

    # Очищаем существующую таблицу
    if sudo nft list tables 2>/dev/null | grep -q "$table"; then
        sudo nft flush chain "$table" "$chain" 2>/dev/null
        sudo nft delete chain "$table" "$chain" 2>/dev/null
        sudo nft delete table "$table" 2>/dev/null
    fi

    # Создаём таблицу и цепочку
    sudo nft add table "$table"
    sudo nft add chain "$table" "$chain" { type filter hook output priority 0\; }

    # Добавляем TCP правило
    if [[ -n "$tcp_ports" ]]; then
        sudo nft add rule "$table" "$chain" $oif_clause \
            meta mark != "$mark" tcp dport "{$tcp_ports}" \
            counter queue num "$queue_num" bypass \
            comment "\"$comment\""
    fi

    # Добавляем UDP правило
    if [[ -n "$udp_ports" ]]; then
        sudo nft add rule "$table" "$chain" $oif_clause \
            meta mark != "$mark" udp dport "{$udp_ports}" \
            counter queue num "$queue_num" bypass \
            comment "\"$comment\""
    fi
}

# -----------------------------------------------------------------------------
# nft_clear - удаляет таблицу и цепочку nftables
# -----------------------------------------------------------------------------
# Аргументы:
#   $1 - table   (опционально, по умолчанию $NFT_TABLE)
#   $2 - chain   (опционально, по умолчанию $NFT_CHAIN)
# -----------------------------------------------------------------------------
nft_clear() {
    local table="${1:-$NFT_TABLE}"
    local chain="${2:-$NFT_CHAIN}"

    if sudo nft list tables 2>/dev/null | grep -q "$table"; then
        if sudo nft list chain "$table" "$chain" >/dev/null 2>&1; then
            sudo nft flush chain "$table" "$chain" 2>/dev/null
            sudo nft delete chain "$table" "$chain" 2>/dev/null
        fi
        sudo nft delete table "$table" 2>/dev/null
    fi
}
