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
    local reply_chain="${6:-$IPT_CHAIN_REPLY}"

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

    local ipt_sports=""
    if [[ -n "$ipt_tcp" ]]; then
        ipt_sports="${ipt_tcp}"
    fi

    for cmd in iptables ip6tables; do
        elevate "$cmd" -t "$IPT_TABLE" -D POSTROUTING -j "$IPT_CHAIN" 2>/dev/null || true
        elevate "$cmd" -t "$IPT_TABLE" -F "$IPT_CHAIN" 2>/dev/null || true
        elevate "$cmd" -t "$IPT_TABLE" -X "$IPT_CHAIN" 2>/dev/null || true
        elevate "$cmd" -t "$IPT_TABLE" -D PREROUTING -j "$reply_chain" 2>/dev/null || true
        elevate "$cmd" -t "$IPT_TABLE" -F "$reply_chain" 2>/dev/null || true
        elevate "$cmd" -t "$IPT_TABLE" -X "$reply_chain" 2>/dev/null || true

        elevate "$cmd" -t "$IPT_TABLE" -N "$IPT_CHAIN"
        elevate "$cmd" -t "$IPT_TABLE" -A POSTROUTING -j "$IPT_CHAIN"

        if [[ -n "$ipt_tcp" ]]; then
            elevate "$cmd" -t "$IPT_TABLE" -A "$IPT_CHAIN" $oif_clause \
                -p tcp -m multiport --dports "$ipt_tcp" \
                -m connbytes --connbytes-dir=original --connbytes-mode=packets --connbytes 1:6 \
                -m mark ! --mark "$mark" \
                -j NFQUEUE --queue-num "$queue_num" --queue-bypass
        fi

        if [[ -n "$ipt_udp" ]]; then
            elevate "$cmd" -t "$IPT_TABLE" -A "$IPT_CHAIN" $oif_clause \
                -p udp -m multiport --dports "$ipt_udp" \
                -m connbytes --connbytes-dir=original --connbytes-mode=packets --connbytes 1:6 \
                -m mark ! --mark "$mark" \
                -j NFQUEUE --queue-num "$queue_num" --queue-bypass
        fi

        if [[ -n "$ipt_sports" ]]; then
            elevate "$cmd" -t "$IPT_TABLE" -N "$reply_chain"
            elevate "$cmd" -t "$IPT_TABLE" -A PREROUTING -j "$reply_chain"

            elevate "$cmd" -t "$IPT_TABLE" -A "$reply_chain" $oif_clause \
                -p tcp -m multiport --sports "$ipt_sports" \
                -m connbytes --connbytes-dir=reply --connbytes-mode=packets --connbytes 1:3 \
                -m mark ! --mark "$mark" \
                -j NFQUEUE --queue-num "$queue_num" --queue-bypass
        fi
    done
}

backend_clear() {
    local reply_chain="${1:-$IPT_CHAIN_REPLY}"

    for cmd in iptables ip6tables; do
        elevate "$cmd" -t "$IPT_TABLE" -D POSTROUTING -j "$IPT_CHAIN" 2>/dev/null || true
        elevate "$cmd" -t "$IPT_TABLE" -F "$IPT_CHAIN" 2>/dev/null || true
        elevate "$cmd" -t "$IPT_TABLE" -X "$IPT_CHAIN" 2>/dev/null || true
        elevate "$cmd" -t "$IPT_TABLE" -D PREROUTING -j "$reply_chain" 2>/dev/null || true
        elevate "$cmd" -t "$IPT_TABLE" -F "$reply_chain" 2>/dev/null || true
        elevate "$cmd" -t "$IPT_TABLE" -X "$reply_chain" 2>/dev/null || true
    done
}
