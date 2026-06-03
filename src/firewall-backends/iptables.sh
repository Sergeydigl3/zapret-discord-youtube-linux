[[ -n "${_IPTABLES_BACKEND_LOADED:-}" ]] && return 0
_IPTABLES_BACKEND_LOADED=1

backend_check() {
    command -v iptables &>/dev/null || return 1
    command -v ip6tables &>/dev/null || return 1
}

backend_setup() {
    local tcp_ports="${1:-}"
    local udp_ports="${2:-}"
    local interface="${3:-}"
    local queue_num="${4:-$NFT_QUEUE_NUM}"
    local mark="${5:-$NFT_MARK}"

    local oif_clause=""
    if [[ -n "$interface" && "$interface" != "any" ]]; then
        oif_clause="-o $interface"
    fi

    local ipt_tcp="${tcp_ports//\{/}"
    ipt_tcp="${ipt_tcp//\}/}"
    ipt_tcp="${ipt_tcp//-/:}"
    local ipt_udp="${udp_ports//\{/}"
    ipt_udp="${ipt_udp//\}/}"
    ipt_udp="${ipt_udp//-/:}"

    for cmd in iptables ip6tables; do
        elevate "$cmd" -t "$IPT_TABLE" -D OUTPUT -j "$IPT_CHAIN" 2>/dev/null || true
        elevate "$cmd" -t "$IPT_TABLE" -F "$IPT_CHAIN" 2>/dev/null || true
        elevate "$cmd" -t "$IPT_TABLE" -X "$IPT_CHAIN" 2>/dev/null || true

        elevate "$cmd" -t "$IPT_TABLE" -N "$IPT_CHAIN"
        elevate "$cmd" -t "$IPT_TABLE" -A OUTPUT -j "$IPT_CHAIN"

        if [[ -n "$ipt_tcp" ]]; then
            elevate "$cmd" -t "$IPT_TABLE" -A "$IPT_CHAIN" $oif_clause \
                -p tcp -m multiport --dports "$ipt_tcp" \
                -m mark ! --mark "$mark" \
                -j NFQUEUE --queue-num "$queue_num" --queue-bypass
        fi

        if [[ -n "$ipt_udp" ]]; then
            elevate "$cmd" -t "$IPT_TABLE" -A "$IPT_CHAIN" $oif_clause \
                -p udp -m multiport --dports "$ipt_udp" \
                -m mark ! --mark "$mark" \
                -j NFQUEUE --queue-num "$queue_num" --queue-bypass
        fi
    done
}

backend_clear() {
    for cmd in iptables ip6tables; do
        elevate "$cmd" -t "$IPT_TABLE" -D OUTPUT -j "$IPT_CHAIN" 2>/dev/null || true
        elevate "$cmd" -t "$IPT_TABLE" -F "$IPT_CHAIN" 2>/dev/null || true
        elevate "$cmd" -t "$IPT_TABLE" -X "$IPT_CHAIN" 2>/dev/null || true
    done
}
