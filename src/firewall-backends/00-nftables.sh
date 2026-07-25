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
    local chain_pre="${9:-$NFT_CHAIN_PRE}"

    local oif_clause=""
    local iif_clause=""
    if [[ -n "$interface" && "$interface" != "any" ]]; then
        oif_clause="oifname \"$interface\""
        iif_clause="iifname \"$interface\""
    fi

    if elevate nft list tables 2>/dev/null | grep -q "$table"; then
        elevate nft flush chain "$table" "$chain" 2>/dev/null
        elevate nft delete chain "$table" "$chain" 2>/dev/null
        elevate nft flush chain "$table" "$chain_pre" 2>/dev/null
        elevate nft delete chain "$table" "$chain_pre" 2>/dev/null
        elevate nft delete table "$table" 2>/dev/null
    fi

    elevate nft add table "$table"
    elevate nft add chain "$table" "$chain" { type filter hook postrouting priority mangle\; }
    elevate nft add chain "$table" "$chain_pre" { type filter hook prerouting priority filter\; }

    if [[ -n "$tcp_ports" ]]; then
        elevate nft add rule "$table" "$chain" $oif_clause \
            meta mark and "$mark" == 0 tcp dport "{$tcp_ports}" \
            ct original packets 1-6 queue num "$queue_num" bypass \
            comment "\"$comment\""
    fi

    if [[ -n "$udp_ports" ]]; then
        elevate nft add rule "$table" "$chain" $oif_clause \
            meta mark and "$mark" == 0 udp dport "{$udp_ports}" \
            ct original packets 1-6 queue num "$queue_num" bypass \
            comment "\"$comment\""
    fi

    if [[ -n "$tcp_ports" ]]; then
        elevate nft add rule "$table" "$chain_pre" $iif_clause \
            tcp sport "{$tcp_ports}" \
            ct reply packets 1-3 queue num "$queue_num" bypass \
            comment "\"$comment\""
    fi
}

backend_clear() {
    local table="${1:-$NFT_TABLE}"
    local chain="${2:-$NFT_CHAIN}"
    local chain_pre="${3:-$NFT_CHAIN_PRE}"

    if elevate nft list tables 2>/dev/null | grep -q "$table"; then
        if elevate nft list chain "$table" "$chain" >/dev/null 2>&1; then
            elevate nft flush chain "$table" "$chain" 2>/dev/null
            elevate nft delete chain "$table" "$chain" 2>/dev/null
        fi
        if elevate nft list chain "$table" "$chain_pre" >/dev/null 2>&1; then
            elevate nft flush chain "$table" "$chain_pre" 2>/dev/null
            elevate nft delete chain "$table" "$chain_pre" 2>/dev/null
        fi
        elevate nft delete table "$table" 2>/dev/null
    fi
}
