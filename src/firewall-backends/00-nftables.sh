[[ -n "${_NFTABLES_BACKEND_LOADED:-}" ]] && return 0
_NFTABLES_BACKEND_LOADED=1

backend_check() {
    command -v nft &>/dev/null || return 1
}

backend_setup() {
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

    if elevate nft list tables 2>/dev/null | grep -q "$table"; then
        elevate nft flush chain "$table" "$chain" 2>/dev/null
        elevate nft delete chain "$table" "$chain" 2>/dev/null
        elevate nft delete table "$table" 2>/dev/null
    fi

    elevate nft add table "$table"
    elevate nft add chain "$table" "$chain" { type filter hook output priority 0\; }

    if [[ -n "$tcp_ports" ]]; then
        elevate nft add rule "$table" "$chain" $oif_clause \
            meta mark != "$mark" tcp dport "{$tcp_ports}" \
            counter queue num "$queue_num" bypass \
            comment "\"$comment\""
    fi

    if [[ -n "$udp_ports" ]]; then
        elevate nft add rule "$table" "$chain" $oif_clause \
            meta mark != "$mark" udp dport "{$udp_ports}" \
            counter queue num "$queue_num" bypass \
            comment "\"$comment\""
    fi
}

backend_clear() {
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
