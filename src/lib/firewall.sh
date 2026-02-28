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
# nft_setup - создаёт таблицу, цепочку и правила nftables с поддержкой ROUTER_MODE
# -----------------------------------------------------------------------------
# Аргументы:
#   $1 - tcp_ports   (например: "80,443" или "")
#   $2 - udp_ports   (например: "443,50000-50100" или "")
#   $3 - interface   (например: "eth0" или "any" или "")
#   $4 - table       (опционально, по умолчанию $NFT_TABLE)
#   $5 - common_chain (опционально, по умолчанию $NFT_COMMON_CHAIN)
#   $6 - queue_num   (опционально, по умолчанию $NFT_QUEUE_NUM)
#   $7 - mark        (опционально, по умолчанию $NFT_MARK)
#   $8 - comment     (опционально, по умолчанию $NFT_RULE_COMMENT)
# -----------------------------------------------------------------------------
nft_setup() {
    local tcp_ports="${1:-}"
    local udp_ports="${2:-}"
    local interface="${3:-}"
    local table_inet="${4:-$NFT_TABLE}"
    local common_chain="${5:-$NFT_COMMON_CHAIN}"
    local queue_num="${6:-$NFT_QUEUE_NUM}"
    local mark="${7:-$NFT_MARK}"
    local comment="${8:-$NFT_RULE_COMMENT}"

    log "Настройка nftables (ROUTER_MODE=${ROUTER_MODE:-0})..."

    # Очистка только наших таблиц
    elevate nft delete table inet zapretunix 2>/dev/null || true
    elevate nft delete table ip zapretunix 2>/dev/null || true

    # ========== inet table ==========
    log "Создание таблицы inet zapretunix..."
    elevate nft add table inet zapretunix || handle_error "Ошибка создания inet таблицы"

    # Общая логическая цепочка
    log "Создание цепочки $common_chain..."
    elevate nft add chain "$table_inet" "$common_chain" || handle_error "Ошибка создания цепочки $common_chain"

    # OUTPUT — всегда
    log "Создание цепочки output..."
    elevate nft add chain "$table_inet" output '{
        type filter hook output priority mangle;
        policy accept;
    }' || handle_error "Ошибка создания цепочки output"

    elevate nft add rule "$table_inet" output jump "$common_chain" || handle_error "Ошибка добавления правила jump в output"

    # FORWARD — только если router mode
    if [[ "$ROUTER_MODE" == "1" ]]; then
        log "Создание цепочки forward (router mode)..."
        elevate nft add chain "$table_inet" forward '{
            type filter hook forward priority mangle;
            policy accept;
        }' || handle_error "Ошибка создания цепочки forward"

        elevate nft add rule "$table_inet" forward jump "$common_chain" || handle_error "Ошибка добавления правила jump в forward"
    fi

    # Исключаем локальные сети
    log "Добавление правил исключения локальных сетей..."
    elevate nft add rule "$table_inet" "$common_chain" \
        ip daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 255.255.255.255 } \
        return || handle_error "Ошибка добавления правила исключения локальных сетей"

    local oif_clause=""
    if [[ -n "$interface" && "$interface" != "any" ]]; then
        oif_clause="oifname \"$interface\""
        log "Используется интерфейс: $interface"
    fi

    # TCP
    if [[ -n "$tcp_ports" ]]; then
        log "Добавление TCP правил для портов: $tcp_ports"
        if [[ -n "$oif_clause" ]]; then
            elevate nft add rule "$table_inet" "$common_chain" \
                $oif_clause meta mark != "$mark" \
                tcp dport { $tcp_ports } \
                counter queue num "$queue_num" bypass \
                comment "\"$comment\"" \
            || handle_error "Ошибка при добавлении TCP правила nftables"
        else
            elevate nft add rule "$table_inet" "$common_chain" \
                meta mark != "$mark" \
                tcp dport { $tcp_ports } \
                counter queue num "$queue_num" bypass \
                comment "\"$comment\"" \
            || handle_error "Ошибка при добавлении TCP правила nftables"
        fi
    fi

    # UDP
    if [[ -n "$udp_ports" ]]; then
        log "Добавление UDP правил для портов: $udp_ports"
        if [[ -n "$oif_clause" ]]; then
            elevate nft add rule "$table_inet" "$common_chain" \
                $oif_clause meta mark != "$mark" \
                udp dport { $udp_ports } \
                counter queue num "$queue_num" bypass \
                comment "\"$comment\"" \
            || handle_error "Ошибка при добавлении UDP правила nftables"
        else
            elevate nft add rule "$table_inet" "$common_chain" \
                meta mark != "$mark" \
                udp dport { $udp_ports } \
                counter queue num "$queue_num" bypass \
                comment "\"$comment\"" \
            || handle_error "Ошибка при добавлении UDP правила nftables"
        fi
    fi

    # ========== NAT (только router mode) ==========
    if [[ "$ROUTER_MODE" == "1" ]]; then
        log "Настройка NAT (router mode)..."
        elevate nft add table ip zapretunix || handle_error "Ошибка создания ip таблицы"
        elevate nft add chain ip zapretunix postrouting '{
            type nat hook postrouting priority srcnat;
        }' || handle_error "Ошибка создания цепочки postrouting"
        elevate nft add rule ip zapretunix postrouting oifname "$interface" masquerade || handle_error "Ошибка добавления правила masquerade"
    fi

    log "Настройка nftables завершена успешно"
}

# -----------------------------------------------------------------------------
# nft_clear - удаляет таблицы nftables (inet и ip)
# -----------------------------------------------------------------------------
nft_clear() {
    log "Очистка nftables (zapretunix)..."

    # inet table — всегда
    if elevate nft list table inet zapretunix >/dev/null 2>&1; then
        elevate nft delete table inet zapretunix \
            && log "Удалена таблица inet zapretunix" \
            || log "Ошибка при удалении inet zapretunix"
    else
        log "Таблица inet zapretunix не найдена"
    fi

    # ip table — только если был router mode
    if elevate nft list table ip zapretunix >/dev/null 2>&1; then
        elevate nft delete table ip zapretunix \
            && log "Удалена таблица ip zapretunix" \
            || log "Ошибка при удалении ip zapretunix"
    else
        log "Таблица ip zapretunix не найдена"
    fi

    log "Очистка nftables завершена"
}
