#!/usr/bin/env bash

# =============================================================================
# Функции для работы с nftables и iptables
# =============================================================================

# Подключаем константы если ещё не подключены
if [[ -z "$NFT_TABLE" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/constants.sh"
fi

# -----------------------------------------------------------------------------
# Определение активного бэкенда файрвола
# -----------------------------------------------------------------------------
# Поддерживаемые значения: nftables, iptables
# Если FIREWALL_BACKEND=auto, определяется автоматически
# -----------------------------------------------------------------------------
detect_firewall_backend() {
    local backend="${FIREWALL_BACKEND:-auto}"

    if [[ "$backend" == "auto" ]]; then
        if command -v nft &>/dev/null; then
            echo "nftables"
        elif command -v iptables &>/dev/null && command -v ip6tables &>/dev/null; then
            echo "iptables"
        else
            echo "none"
        fi
    else
        if [[ "$backend" == "nftables" ]] && ! command -v nft &>/dev/null; then
            echo "Ошибка: выбран nftables, но nft не установлен" >&2
            return 1
        elif [[ "$backend" == "iptables" ]]; then
            if ! command -v iptables &>/dev/null; then
                echo "Ошибка: выбран iptables, но iptables не установлен" >&2
                return 1
            fi
            if ! command -v ip6tables &>/dev/null; then
                echo "Ошибка: выбран iptables, но ip6tables не установлен" >&2
                return 1
            fi
        fi
        echo "$backend"
    fi
}

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
    if elevate nft list tables 2>/dev/null | grep -q "$table"; then
        elevate nft flush chain "$table" "$chain" 2>/dev/null
        elevate nft delete chain "$table" "$chain" 2>/dev/null
        elevate nft delete table "$table" 2>/dev/null
    fi

    # Создаём таблицу и цепочку
    elevate nft add table "$table"
    elevate nft add chain "$table" "$chain" { type filter hook output priority 0\; }

    # Добавляем TCP правило
    if [[ -n "$tcp_ports" ]]; then
        elevate nft add rule "$table" "$chain" $oif_clause \
            meta mark != "$mark" tcp dport "{$tcp_ports}" \
            counter queue num "$queue_num" bypass \
            comment "\"$comment\""
    fi

    # Добавляем UDP правило
    if [[ -n "$udp_ports" ]]; then
        elevate nft add rule "$table" "$chain" $oif_clause \
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

    if elevate nft list tables 2>/dev/null | grep -q "$table"; then
        if elevate nft list chain "$table" "$chain" >/dev/null 2>&1; then
            elevate nft flush chain "$table" "$chain" 2>/dev/null
            elevate nft delete chain "$table" "$chain" 2>/dev/null
        fi
        elevate nft delete table "$table" 2>/dev/null
    fi
}

# -----------------------------------------------------------------------------
# ipt_setup - создаёт цепочку и правила iptables/ip6tables
# -----------------------------------------------------------------------------
# Аргументы:
#   $1 - tcp_ports   (например: "80,443" или "")
#   $2 - udp_ports   (например: "443,50000-50100" или "")
#   $3 - interface   (например: "eth0" или "any" или "")
#   $4 - queue_num   (опционально, по умолчанию $NFT_QUEUE_NUM)
#   $5 - mark        (опционально, по умолчанию $NFT_MARK)
# -----------------------------------------------------------------------------
ipt_setup() {
    local tcp_ports="${1:-}"
    local udp_ports="${2:-}"
    local interface="${3:-}"
    local queue_num="${4:-$NFT_QUEUE_NUM}"
    local mark="${5:-$NFT_MARK}"

    local oif_clause=""
    if [[ -n "$interface" && "$interface" != "any" ]]; then
        oif_clause="-o $interface"
    fi

    # Преобразуем порты из nftables в iptables формат:
    #   {80,443} -> 80,443  (удаляем фигурные скобки)
    #   1024-65535 -> 1024:65535  (диапазоны через двоеточие)
    local ipt_tcp="${tcp_ports//\{/}"
    ipt_tcp="${ipt_tcp//\}/}"
    ipt_tcp="${ipt_tcp//-/:}"
    local ipt_udp="${udp_ports//\{/}"
    ipt_udp="${ipt_udp//\}/}"
    ipt_udp="${ipt_udp//-/:}"

    for cmd in iptables ip6tables; do
        # Удаляем из OUTPUT цепочки, если существует
        elevate "$cmd" -t "$IPT_TABLE" -D OUTPUT -j "$IPT_CHAIN" 2>/dev/null || true
        # Очищаем и удаляем кастомную цепочку
        elevate "$cmd" -t "$IPT_TABLE" -F "$IPT_CHAIN" 2>/dev/null || true
        elevate "$cmd" -t "$IPT_TABLE" -X "$IPT_CHAIN" 2>/dev/null || true

        # Создаём цепочку и добавляем в OUTPUT
        elevate "$cmd" -t "$IPT_TABLE" -N "$IPT_CHAIN"
        elevate "$cmd" -t "$IPT_TABLE" -A OUTPUT -j "$IPT_CHAIN"

        # TCP правила
        if [[ -n "$ipt_tcp" ]]; then
            elevate "$cmd" -t "$IPT_TABLE" -A "$IPT_CHAIN" $oif_clause \
                -p tcp -m multiport --dports "$ipt_tcp" \
                -m mark ! --mark "$mark" \
                -j NFQUEUE --queue-num "$queue_num" --queue-bypass
        fi

        # UDP правила
        if [[ -n "$ipt_udp" ]]; then
            elevate "$cmd" -t "$IPT_TABLE" -A "$IPT_CHAIN" $oif_clause \
                -p udp -m multiport --dports "$ipt_udp" \
                -m mark ! --mark "$mark" \
                -j NFQUEUE --queue-num "$queue_num" --queue-bypass
        fi
    done
}

# -----------------------------------------------------------------------------
# ipt_clear - удаляет цепочку и правила iptables/ip6tables
# -----------------------------------------------------------------------------
ipt_clear() {
    for cmd in iptables ip6tables; do
        elevate "$cmd" -t "$IPT_TABLE" -D OUTPUT -j "$IPT_CHAIN" 2>/dev/null || true
        elevate "$cmd" -t "$IPT_TABLE" -F "$IPT_CHAIN" 2>/dev/null || true
        elevate "$cmd" -t "$IPT_TABLE" -X "$IPT_CHAIN" 2>/dev/null || true
    done
}

# -----------------------------------------------------------------------------
# firewall_setup - создаёт правила используя активный бэкенд
# -----------------------------------------------------------------------------
# Аргументы:
#   $1 - tcp_ports
#   $2 - udp_ports
#   $3 - interface
# -----------------------------------------------------------------------------
firewall_setup() {
    local backend
    backend=$(detect_firewall_backend) || return 1

    case "$backend" in
        nftables)
            nft_setup "$1" "$2" "$3"
            ;;
        iptables)
            ipt_setup "$1" "$2" "$3"
            ;;
        none)
            handle_error "Не найден nftables или iptables. Установите один из них."
            ;;
    esac

    log "Настройка $backend завершена (TCP: ${1:-—}, UDP: ${2:-—})"
}

# -----------------------------------------------------------------------------
# firewall_clear - удаляет правила используя активный бэкенд
# -----------------------------------------------------------------------------
firewall_clear() {
    local backend
    backend=$(detect_firewall_backend) || return 1

    case "$backend" in
        nftables)
            nft_clear
            ;;
        iptables)
            ipt_clear
            ;;
    esac
}
