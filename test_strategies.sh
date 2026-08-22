#!/usr/bin/env bash
#
# Тест стратегий по аналогии с Flowseal utils/test zapret.ps1.
# Цели по умолчанию: zapret-latest/utils/targets.txt.
# Опционально: домены из lists/list-*.txt (--from-lists).
#
# Требования: ./service.sh download-deps, curl, ping, sudo/root для run/kill.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_SCRIPT="$SCRIPT_DIR/service.sh"
REPO_DIR="$SCRIPT_DIR/zapret-latest"
LISTS_DIR="$REPO_DIR/lists"
TARGETS_FILE="$REPO_DIR/utils/targets.txt"
CURL_TIMEOUT=5
CURL_CONNECT_TIMEOUT=5
PING_COUNT=3
PING_WAIT=2
NFQWS_START_TIMEOUT=120
STOP_SLEEP=1
PARALLEL_JOBS=8
MAX_NAME_LEN=10

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'
BOLD='\033[1m'

USE_FROM_LISTS=false
LIST_SOURCES=()
IPSET_ANY=false
IPSET_DID_SWITCH=false
QUICK_MODE=false
NO_PING=false
SELECTED_STRATEGIES=()

declare -a STRATEGIES=()
declare -a TARGET_NAMES=()
declare -a TARGET_URLS=()      # empty = ping-only
declare -a TARGET_PING=()

declare -A ANALYTICS_OK=()
declare -A ANALYTICS_ERR=()
declare -A ANALYTICS_UNSUP=()
declare -A ANALYTICS_PING_OK=()
declare -A ANALYTICS_PING_FAIL=()
declare -A EXCLUDE_DOMAINS=()

START_STRATEGY_LOG=""

usage() {
    cat <<'EOF'
Usage: sudo ./test_strategies.sh [options]

Проверяет каждую стратегию (service.sh run) и доступность целей через curl/ping,
по логике Windows «Standard tests» (utils/test zapret.ps1).

Options:
  -h, --help              Справка
  --fast                  Быстрый режим: TLS1.3, таймауты 3с, ping×1, 8 целей параллельно
  --quick                 Только TLS 1.3 (без HTTP/TLS1.2)
  --no-ping               Не делать ping
  --essential             Только Discord/YouTube/Google (≈8 целей вместо 17)
  -j, --jobs N            Параллельно проверять N целей (1 = по порядку)
  --ipset-any             На время теста перевести ipset в режим «Any» (как в auto_tune)
  --from-lists [a,b]      Добавить цели из lists/list-*.txt
                          (general, google или all; без аргумента — general+google)
  --targets-file PATH     Файл целей в формате targets.txt
  -s, --strategy NAME     Тестировать только указанные .bat (можно несколько раз)

Цели по умолчанию: zapret-latest/utils/targets.txt
Файлы lists/list-*.txt — hostlist для nfqws; для теста используйте --from-lists.

Примеры:
  sudo ./test_strategies.sh --fast
  sudo ./test_strategies.sh --fast --essential -s general.bat
  sudo ./test_strategies.sh -j 8 --quick --no-ping
EOF
}

log_info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        log_error "Не найдена команда: $1"
        exit 1
    }
}

init_zapret_libs() {
    [[ -n "${_ZAPRET_TEST_LIB_LOADED:-}" ]] && return 0
    _ZAPRET_TEST_LIB_LOADED=1
    export BASE_DIR="$SCRIPT_DIR"
    export REPO_DIR="$SCRIPT_DIR/zapret-latest"
    export NFQWS_PATH="$SCRIPT_DIR/nfqws"
    export CUSTOM_STRATEGIES_DIR="$SCRIPT_DIR/custom-strategies"
    # shellcheck source=src/lib/elevate.sh
    source "$SCRIPT_DIR/src/lib/elevate.sh"
    # shellcheck source=src/lib/constants.sh
    source "$SCRIPT_DIR/src/lib/constants.sh"
    # shellcheck source=src/lib/common.sh
    source "$SCRIPT_DIR/src/lib/common.sh"
    # shellcheck source=src/lib/firewall.sh
    source "$SCRIPT_DIR/src/lib/firewall.sh"
    # shellcheck source=src/lib/test_nfqws_quiet.sh
    source "$SCRIPT_DIR/src/lib/test_nfqws_quiet.sh"
}

stop_zapret() {
    "$SERVICE_SCRIPT" kill >/dev/null 2>&1 || true
    sleep "$STOP_SLEEP"
}

apply_fast_mode() {
    QUICK_MODE=true
    CURL_TIMEOUT=3
    CURL_CONNECT_TIMEOUT=2
    PING_COUNT=1
    PING_WAIT=1
    STOP_SLEEP=0.5
    PARALLEL_JOBS=8
}

reset_test_settings() {
    QUICK_MODE=false
    NO_PING=false
    USE_FROM_LISTS=false
    LIST_SOURCES=()
    IPSET_ANY=false
    IPSET_DID_SWITCH=false
    SELECTED_STRATEGIES=()
    CUSTOM_TARGETS_FILE=""
    CURL_TIMEOUT=5
    CURL_CONNECT_TIMEOUT=5
    PING_COUNT=3
    PING_WAIT=2
    STOP_SLEEP=1
    PARALLEL_JOBS=8
    TARGETS_MODE="essential"
}

# default | essential | lists | custom
TARGETS_MODE="essential"

# Запуск без service.sh run
start_strategy() {
    local name="$1"
    init_zapret_libs

    strategy="$name"
    interface="any"
    gamefiltertcp="false"
    gamefilterudp="false"

    rm -f "$START_STRATEGY_LOG" 2>/dev/null || true
    START_STRATEGY_LOG="$(mktemp)"

    log_info "[$name] Запуск стратегии..."
    if ( run_zapret ) >"$START_STRATEGY_LOG" 2>&1; then
        return 0
    fi
    return 1
}

wait_for_nfqws() {
    local _name="$1"
    timeout "${NFQWS_START_TIMEOUT}s" tail -n +1 -f "$START_STRATEGY_LOG" 2>/dev/null | \
        grep -qE "Настройка успешно завершена|Ошибка|error|failed" || true
    pgrep -f nfqws >/dev/null 2>&1
}

# targets

add_target() {
    local name="$1"
    local url="${2:-}"
    local ping="${3:-}"

    TARGET_NAMES+=("$name")
    TARGET_URLS+=("$url")
    TARGET_PING+=("$ping")
}

load_targets_file() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*\"(.+)\"[[:space:]]*$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            if [[ "$val" =~ ^[Pp][Ii][Nn][Gg]:[[:space:]]*(.+)$ ]]; then
                add_target "$key" "" "${BASH_REMATCH[1]}"
            else
                add_target "$key" "$val" ""
            fi
        fi
    done < "$file"
    return 0
}

load_essential_targets_file() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*\"(.+)\"[[:space:]]*$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            local key_lc val_lc
            key_lc="$(echo "$key" | tr '[:upper:]' '[:lower:]')"
            val_lc="$(echo "$val" | tr '[:upper:]' '[:lower:]')"
            if [[ ! "$key_lc" =~ discord|youtube|youtu|google ]] &&
               [[ ! "$val_lc" =~ discord|youtube|youtu\.be|google|googlevideo|gstatic ]]; then
                continue
            fi
            if [[ "$val" =~ ^[Pp][Ii][Nn][Gg]:[[:space:]]*(.+)$ ]]; then
                add_target "$key" "" "${BASH_REMATCH[1]}"
            else
                add_target "$key" "$val" ""
            fi
        fi
    done < "$file"
    return 0
}

load_default_targets() {
    add_target "DiscordMain" "https://discord.com" ""
    add_target "DiscordGateway" "https://gateway.discord.gg" ""
    add_target "DiscordCDN" "https://cdn.discordapp.com" ""
    add_target "DiscordUpdates" "https://updates.discord.com" ""
    add_target "YouTubeWeb" "https://www.youtube.com" ""
    add_target "YouTubeShort" "https://youtu.be" ""
    add_target "YouTubeImage" "https://i.ytimg.com" ""
    add_target "YouTubeVideoRedirect" "https://redirector.googlevideo.com" ""
    add_target "GoogleMain" "https://www.google.com" ""
    add_target "GoogleGstatic" "https://www.gstatic.com" ""
    add_target "CloudflareWeb" "https://www.cloudflare.com" ""
    add_target "CloudflareCDN" "https://cdnjs.cloudflare.com" ""
    add_target "CloudflareDNS1111" "" "1.1.1.1"
    add_target "CloudflareDNS1001" "" "1.0.0.1"
    add_target "GoogleDNS8888" "" "8.8.8.8"
    add_target "GoogleDNS8844" "" "8.8.4.4"
    add_target "Quad9DNS9999" "" "9.9.9.9"
}

load_default_essential_targets() {
    add_target "DiscordMain" "https://discord.com" ""
    add_target "DiscordGateway" "https://gateway.discord.gg" ""
    add_target "DiscordCDN" "https://cdn.discordapp.com" ""
    add_target "YouTubeWeb" "https://www.youtube.com" ""
    add_target "YouTubeShort" "https://youtu.be" ""
    add_target "YouTubeVideoRedirect" "https://redirector.googlevideo.com" ""
    add_target "GoogleMain" "https://www.google.com" ""
    add_target "GoogleGstatic" "https://www.gstatic.com" ""
}

load_exclude_domains() {
    local f="$LISTS_DIR/list-exclude.txt"
    local line
    EXCLUDE_DOMAINS=()
    [[ -f "$f" ]] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="$(echo "$line" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ -z "$line" ]] && continue
        EXCLUDE_DOMAINS["$line"]=1
    done < "$f"
}

domain_in_exclude() {
    local domain="$1"
    [[ -n "${EXCLUDE_DOMAINS[$domain]:-}" ]]
}

load_domains_from_list() {
    local list_name="$1"
    local path="$LISTS_DIR/list-${list_name}.txt"
    [[ -f "$path" ]] || {
        log_warn "Нет файла: $path"
        return 0
    }

    while IFS= read -r domain || [[ -n "$domain" ]]; do
        domain="${domain%%#*}"
        domain="$(echo "$domain" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ -z "$domain" ]] && continue
        domain_in_exclude "$domain" && continue
        local key="list_${list_name}_${domain}"
        key="${key//[^A-Za-z0-9_]/_}"
        add_target "$key" "https://${domain}" ""
    done < "$path"
}

load_from_lists() {
    local -a sources=()
    if [[ ${#LIST_SOURCES[@]} -eq 0 ]]; then
        sources=(general google)
    else
        sources=("${LIST_SOURCES[@]}")
    fi

    load_exclude_domains

    for src in "${sources[@]}"; do
        if [[ "$src" == "all" ]]; then
            for f in "$LISTS_DIR"/list-*.txt; do
                [[ -f "$f" ]] || continue
                local base
                base="$(basename "$f" .txt)"
                base="${base#list-}"
                [[ "$base" == "exclude" ]] && continue
                load_domains_from_list "$base"
            done
        else
            load_domains_from_list "$src"
        fi
    done
}

dedupe_targets() {
    local -a n=() u=() p=()
    local -A seen=()
    local i name key

    for i in "${!TARGET_NAMES[@]}"; do
        name="${TARGET_NAMES[$i]}"
        key="${name}|${TARGET_URLS[$i]}|${TARGET_PING[$i]}"
        [[ -n "${seen[$key]:-}" ]] && continue
        seen[$key]=1
        n+=("$name")
        u+=("${TARGET_URLS[$i]}")
        p+=("${TARGET_PING[$i]}")
    done
    TARGET_NAMES=("${n[@]}")
    TARGET_URLS=("${u[@]}")
    TARGET_PING=("${p[@]}")
}

# curl / ping

curl_probe() {
    local url="$1"
    local label="$2"
    local -a extra=()
    local out code

    case "$label" in
        HTTP)   extra=(--http1.1) ;;
        TLS1.2) extra=(--tlsv1.2 --tls-max 1.2) ;;
        TLS1.3) extra=(--tlsv1.3 --tls-max 1.3) ;;
        *) return 1 ;;
    esac

    out="$(curl -I -s --connect-timeout "$CURL_CONNECT_TIMEOUT" -m "$CURL_TIMEOUT" \
        -o /dev/null -w '%{http_code}' \
        "${extra[@]}" --show-error "$url" 2>&1)"
    code=$?

    if echo "$out" | grep -qiE 'could not resolve host|certificate|SSL certificate|self[- ]?signed|unable to get local issuer'; then
        echo "SSL"
        return 0
    fi
    if [[ $code -eq 35 ]] || echo "$out" | grep -qiE 'not supported|unsupported protocol|Unrecognized option|Unknown option'; then
        echo "UNSUP"
        return 0
    fi
    if [[ $code -eq 0 ]]; then
        echo "OK"
        return 0
    fi
    echo "ERROR"
}

ping_probe() {
    local host="$1"
    if ping -c "$PING_COUNT" -W "$PING_WAIT" "$host" >/dev/null 2>&1; then
        local ms
        ms="$(ping -c "$PING_COUNT" -W "$PING_WAIT" "$host" 2>/dev/null | tail -1 | sed -n 's/.*= \([^/]*\).*/\1/p')"
        [[ -n "$ms" ]] && echo "$ms" || echo "OK"
    else
        echo "Timeout"
    fi
}

LAST_PROBE_TOKENS=""
LAST_PROBE_PING="n/a"

probe_target() {
    local url="$1" ping_host="$2"
    local -a tokens=()
    local ping_res="n/a"
    local label result ping_target
    local curl_error=false

    if [[ -n "$url" ]]; then
        if $QUICK_MODE; then
            result="$(curl_probe "$url" "TLS1.3")"
            tokens+=("TLS1.3:${result}")
            [[ "$result" == "ERROR" ]] && curl_error=true
        else
            for label in HTTP TLS1.2 TLS1.3; do
                result="$(curl_probe "$url" "$label")"
                tokens+=("${label}:${result}")
                [[ "$result" == "ERROR" ]] && curl_error=true
            done
        fi
        ping_target="${url#https://}"
        ping_target="${ping_target#http://}"
        ping_target="${ping_target%%/*}"
    fi

    if [[ -n "$ping_host" ]]; then
        ping_target="$ping_host"
    fi

    if ! $NO_PING && ! $curl_error && [[ -n "${ping_target:-}" ]]; then
        ping_res="$(ping_probe "$ping_target")"
    fi

    LAST_PROBE_TOKENS="${tokens[*]}"
    LAST_PROBE_PING="$ping_res"
}

show_target_result() {
    local name="$1" url="$2" ping_host="$3" tokens="$4" ping_res="$5"
    local conn
    local -a tok_arr=()

    conn="$(target_connection_label "$url" "$ping_host")"
    printf '  %-*s ' "$MAX_NAME_LEN" "$name"
    echo -ne "${DIM}(${conn})${NC}"

    if [[ -n "$tokens" ]]; then
        read -ra tok_arr <<< "$tokens"
        for tok in "${tok_arr[@]}"; do
            print_token "$tok"
        done
        if [[ "$ping_res" != "n/a" ]]; then
            echo -ne " ${DIM}|${NC} Ping: "
            if [[ "$ping_res" == "Timeout" ]]; then
                echo -e "${YELLOW}Timeout${NC}"
            else
                echo -e "${CYAN}${ping_res}${NC}"
            fi
        else
            echo ""
        fi
    else
        echo -ne " Ping: "
        if [[ "$ping_res" == "Timeout" ]]; then
            echo -e "${RED}Timeout${NC}"
        else
            echo -e "${CYAN}${ping_res}${NC}"
        fi
    fi
}

# Цветной вывод метки HTTP:OK / TLS1.2:ERROR
print_token() {
    local tok="$1"
    local status="${tok#*:}"
    local label="${tok%%:*}"

    case "$status" in
        OK)   echo -ne " ${label}:${GREEN}OK${NC}" ;;
        UNSUP) echo -ne " ${label}:${YELLOW}UNSUP${NC}" ;;
        SSL)  echo -ne " ${label}:${YELLOW}SSL${NC}" ;;
        *)    echo -ne " ${label}:${RED}ERROR${NC}" ;;
    esac
}

target_connection_label() {
    local url="$1" ping_host="$2"
    if [[ -n "$url" ]]; then
        echo "$url"
    elif [[ -n "$ping_host" ]]; then
        echo "PING:${ping_host}"
    else
        echo "?"
    fi
}

show_target_line() {
    local name="$1" url="$2" ping_host="$3"
    probe_target "$url" "$ping_host"
    show_target_result "$name" "$url" "$ping_host" "$LAST_PROBE_TOKENS" "$LAST_PROBE_PING"
}

run_targets_for_strategy() {
    local strategy="$1"
    local idx tmpdir
    local running=0

    if (( PARALLEL_JOBS <= 1 )); then
        for idx in "${!TARGET_NAMES[@]}"; do
            show_target_line "${TARGET_NAMES[$idx]}" "${TARGET_URLS[$idx]}" "${TARGET_PING[$idx]}"
            record_line "$strategy" "$LAST_PROBE_TOKENS" "$LAST_PROBE_PING"
        done
        return
    fi

    tmpdir="$(mktemp -d)"
    for idx in "${!TARGET_NAMES[@]}"; do
        (
            probe_target "${TARGET_URLS[$idx]}" "${TARGET_PING[$idx]}"
            printf '%s\n' "$LAST_PROBE_TOKENS" > "$tmpdir/$idx.tokens"
            printf '%s\n' "$LAST_PROBE_PING" > "$tmpdir/$idx.ping"
        ) &
        ((running++))
        if (( running >= PARALLEL_JOBS )); then
            wait -n 2>/dev/null || true
            ((running--))
        fi
    done
    while (( running > 0 )); do
        wait -n 2>/dev/null || true
        ((running--))
    done

    for idx in "${!TARGET_NAMES[@]}"; do
        local tokens ping_res
        [[ -f "$tmpdir/$idx.tokens" ]] || continue
        tokens="$(<"$tmpdir/$idx.tokens")"
        ping_res="$(<"$tmpdir/$idx.ping")"
        show_target_result "${TARGET_NAMES[$idx]}" "${TARGET_URLS[$idx]}" "${TARGET_PING[$idx]}" \
            "$tokens" "$ping_res"
        record_line "$strategy" "$tokens" "$ping_res"
    done
    rm -rf "$tmpdir"
}

compute_max_name_len() {
    local n
    MAX_NAME_LEN=10
    for n in "${TARGET_NAMES[@]}"; do
        if ((${#n} > MAX_NAME_LEN)); then
            MAX_NAME_LEN=${#n}
        fi
    done
}

# strategies / ipset

load_strategies() {
    if [[ ${#SELECTED_STRATEGIES[@]} -gt 0 ]]; then
        STRATEGIES=("${SELECTED_STRATEGIES[@]}")
        return
    fi
    mapfile -t STRATEGIES < <("$SERVICE_SCRIPT" strategy list | grep -E '\.bat$' || true)
    local -a filtered=()
    local line
    for line in "${STRATEGIES[@]}"; do
        [[ "$line" =~ \.bat$ ]] && filtered+=("$line")
    done
    STRATEGIES=("${filtered[@]}")
}

init_analytics() {
    local s
    for s in "${STRATEGIES[@]}"; do
        ANALYTICS_OK[$s]=0
        ANALYTICS_ERR[$s]=0
        ANALYTICS_UNSUP[$s]=0
        ANALYTICS_PING_OK[$s]=0
        ANALYTICS_PING_FAIL[$s]=0
    done
}

record_line() {
    local strategy="$1"
    local tokens="$2"
    local ping_res="$3"
    local tok

    for tok in $tokens; do
        case "$tok" in
            *:OK)     ANALYTICS_OK[$strategy]=$((ANALYTICS_OK[$strategy] + 1)) ;;
            *:UNSUP)  ANALYTICS_UNSUP[$strategy]=$((ANALYTICS_UNSUP[$strategy] + 1)) ;;
            *:SSL|*:ERROR) ANALYTICS_ERR[$strategy]=$((ANALYTICS_ERR[$strategy] + 1)) ;;
        esac
    done

    if [[ "$ping_res" != "n/a" ]]; then
        if [[ "$ping_res" == "Timeout" ]]; then
            ANALYTICS_PING_FAIL[$strategy]=$((ANALYTICS_PING_FAIL[$strategy] + 1))
        else
            ANALYTICS_PING_OK[$strategy]=$((ANALYTICS_PING_OK[$strategy] + 1))
        fi
    fi
}

ipset_switch_any() {
    source "$SCRIPT_DIR/src/lib/ipswitch.sh"
    local mode
    mode="$(get_mode_ipset)"
    if [[ "$mode" != "$ANY" ]]; then
        log_warn "Переключаем ipset в режим «Any» на время теста (--ipset-any)"
        switch_to_any
        IPSET_DID_SWITCH=true
    fi
}

ipset_restore() {
    $IPSET_DID_SWITCH || return
    source "$SCRIPT_DIR/src/lib/ipswitch.sh"
    switch_to_loaded 2>/dev/null || true
}

run_tests_for_strategy() {
    local strategy="$1"
    local idx name url ping_host tokens ping_res conn

    echo ""

    stop_zapret

    log_info "Запуск стратегии..."
    if ! start_strategy "$strategy"; then
        log_warn "[$strategy] не удалось запустить zapret"
        echo "  [SKIP] run_zapret failed"
        stop_zapret
        return 1
    fi

    if ! wait_for_nfqws "$strategy"; then
        log_warn "[$strategy] nfqws не поднялся за ${NFQWS_START_TIMEOUT}с"
        echo "  [SKIP] nfqws timeout"
        stop_zapret
        return 1
    fi

    log_info "Проверка целей..."

    run_targets_for_strategy "$strategy"

    stop_zapret
    rm -f "$START_STRATEGY_LOG" 2>/dev/null || true
    START_STRATEGY_LOG=""
    return 0
}

print_analytics() {
    local best="" best_score=-1 best_ping=-1 s score ping_score
    local a_ok a_err a_unsup a_pok a_pf line_color

    echo ""
    echo -e "${BOLD}=== ANALYTICS ===${NC}"

    for s in "${STRATEGIES[@]}"; do
        a_ok=${ANALYTICS_OK[$s]:-0}
        a_err=${ANALYTICS_ERR[$s]:-0}
        a_unsup=${ANALYTICS_UNSUP[$s]:-0}
        a_pok=${ANALYTICS_PING_OK[$s]:-0}
        a_pf=${ANALYTICS_PING_FAIL[$s]:-0}
        score=$((a_ok * 3 + a_unsup - a_err * 4 + a_pok - a_pf * 2))
        local line="$s : HTTP OK: $a_ok, ERR: $a_err, UNSUP: $a_unsup, Ping OK: $a_pok, Fail: $a_pf, Score: $score"
        if [[ "$a_err" -eq 0 ]]; then
            line_color="$GREEN"
        else
            line_color="$YELLOW"
        fi
        echo -e "${line_color}$line${NC}"

        ping_score=$a_pok
        if [[ $score -gt $best_score ]] || { [[ $score -eq $best_score ]] && [[ $ping_score -gt $best_ping ]]; }; then
            best_score=$score
            best_ping=$ping_score
            best="$s"
        fi
    done

    echo ""
    echo -e "${GREEN}Best strategy: ${best:-none}${NC} ${DIM}(по взвешенному score)${NC}"
}

# интерактивная настройка

show_test_settings_summary() {
    local speed="полный"
    local targets="targets.txt"
    local strategies="все"
    local ping="вкл"
    local ipset_any="нет"

    if (( PARALLEL_JOBS > 1 )) && $QUICK_MODE && (( CURL_TIMEOUT <= 3 )); then
        speed="быстрый"
    elif $QUICK_MODE; then
        speed="TLS1.3"
    fi

    case "$TARGETS_MODE" in
        essential) targets="основные (Discord/YouTube/Google)" ;;
        lists)     targets="targets.txt + lists" ;;
        custom)    targets="файл: $CUSTOM_TARGETS_FILE" ;;
        *)         targets="targets.txt" ;;
    esac

    [[ ${#SELECTED_STRATEGIES[@]} -gt 0 ]] && strategies="выбрано: ${#SELECTED_STRATEGIES[@]}"
    $NO_PING && ping="выкл"
    $IPSET_ANY && ipset_any="да"

    echo "Настройки: скорость=$speed, цели=$targets, стратегии=$strategies, ping=$ping, ipset_any=$ipset_any"
}

menu_test_strategies_pick() {
    local -a all=()
    local line input part n

    while IFS= read -r line; do
        [[ "$line" =~ \.bat$ ]] && all+=("$line")
    done < <("$SERVICE_SCRIPT" strategy list)

    if [[ ${#all[@]} -eq 0 ]]; then
        log_warn "Стратегии не найдены. Сначала: download-deps"
        read -r -p "Enter..."
        return
    fi

    clear
    echo "=============================================================================="
    echo "Выбор стратегий"
    echo "=============================================================================="
    echo "0) Все стратегии"
    local i=1
    for line in "${all[@]}"; do
        printf "  %2d) %s\n" "$i" "$line"
        ((i++))
    done
    echo ""
    echo "Примеры ввода: 0  |  1,3,5  |  2-6  |  1,5-10"
    read -r -p "Номера: " input
    input="${input// /}"

    SELECTED_STRATEGIES=()
    if [[ "$input" == "0" || -z "$input" ]]; then
        return
    fi

    IFS=',' read -ra parts <<< "$input"
    for part in "${parts[@]}"; do
        if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            for ((n = BASH_REMATCH[1]; n <= BASH_REMATCH[2]; n++)); do
                (( n >= 1 && n <= ${#all[@]} )) && SELECTED_STRATEGIES+=("${all[n-1]}")
            done
        elif [[ "$part" =~ ^[0-9]+$ ]]; then
            n=$part
            (( n >= 1 && n <= ${#all[@]} )) && SELECTED_STRATEGIES+=("${all[n-1]}")
        fi
    done

    if [[ ${#SELECTED_STRATEGIES[@]} -eq 0 ]]; then
        log_warn "Ничего не выбрано — будут все стратегии"
    else
        log_info "Выбрано стратегий: ${#SELECTED_STRATEGIES[@]}"
    fi
    read -r -p "Enter..."
}

menu_configure_test() {
    while true; do
        clear
        echo "Настройка теста"
        show_test_settings_summary
        echo ""
        echo "1) Скорость: полный / быстрый"
        echo "2) Цели: стандарт / важные / +lists"
        echo "3) Стратегии: выбрать"
        echo "4) Ping: вкл/выкл"
        echo "5) ipset Any: вкл/выкл"
        echo "6) Сбросить настройки"
        echo "0) Назад"
        echo ""
        read -r -p "Выберите действие: " c
        case "$c" in
            1)
                if (( PARALLEL_JOBS > 1 )) && $QUICK_MODE && (( CURL_TIMEOUT <= 3 )); then
                    QUICK_MODE=false; CURL_TIMEOUT=5; CURL_CONNECT_TIMEOUT=5; PING_COUNT=3; PING_WAIT=2
                    STOP_SLEEP=1; PARALLEL_JOBS=8
                else
                    apply_fast_mode
                fi
                ;;
            2)
                if [[ "$TARGETS_MODE" == "default" ]]; then
                    TARGETS_MODE="essential"; USE_FROM_LISTS=false
                elif [[ "$TARGETS_MODE" == "essential" ]]; then
                    TARGETS_MODE="lists"; USE_FROM_LISTS=true; LIST_SOURCES=(general google)
                else
                    TARGETS_MODE="default"; USE_FROM_LISTS=false
                fi
                CUSTOM_TARGETS_FILE=""
                ;;
            3) menu_test_strategies_pick ;;
            4) if $NO_PING; then NO_PING=false; else NO_PING=true; fi ;;
            5) if $IPSET_ANY; then IPSET_ANY=false; else IPSET_ANY=true; fi ;;
            6) reset_test_settings ;;
            0) return ;;
        esac
    done
}

run_test_interactive_menu() {
    reset_test_settings

    if [[ $EUID -ne 0 ]]; then
        log_error "Тесты требуют root. Запустите: sudo ./service.sh"
        return 1
    fi

    while true; do
        clear
        echo "Тест стратегий"
        show_test_settings_summary
        echo "1) Запустить тест"
        echo "2) Настроить тест"
        echo "0) Назад в главное меню"
        echo ""
        read -r -p "Выберите действие: " c
        case "$c" in
            1)
                echo ""
                read -r -p "Запустить? Отключите VPN. [Y/n]: " ok
                [[ -z "$ok" || "$ok" =~ ^[yYдД]$ ]] || continue
                run_strategy_tests_main || true
                echo ""
                read -r -p "Нажмите Enter..."
                ;;
            2) menu_configure_test ;;
            0) return 0 ;;
        esac
    done
}

# main

CUSTOM_TARGETS_FILE=""

parse_test_cli_args() {
    while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --fast) apply_fast_mode; shift ;;
        --quick) QUICK_MODE=true; shift ;;
        --no-ping) NO_PING=true; shift ;;
        --essential) TARGETS_MODE="essential"; shift ;;
        -j|--jobs)
            shift
            PARALLEL_JOBS="${1:?}"
            [[ "$PARALLEL_JOBS" =~ ^[0-9]+$ ]] || {
                log_error "--jobs: нужно число >= 1"
                exit 1
            }
            (( PARALLEL_JOBS >= 1 )) || PARALLEL_JOBS=1
            shift
            ;;
        --ipset-any) IPSET_ANY=true; shift ;;
        --from-lists)
            USE_FROM_LISTS=true
            TARGETS_MODE="lists"
            shift
            if [[ $# -gt 0 && "$1" != -* ]]; then
                IFS=',' read -ra LIST_SOURCES <<< "$1"
                shift
            fi
            ;;
        --targets-file)
            shift
            CUSTOM_TARGETS_FILE="${1:?}"
            TARGETS_MODE="custom"
            shift
            ;;
        --interactive|-i) shift ;;
        -s|--strategy)
            shift
            SELECTED_STRATEGIES+=("${1:?}")
            shift
            ;;
        *)
            log_error "Неизвестный аргумент: $1"
            usage
            exit 1
            ;;
    esac
    done
}

run_strategy_tests_main() {
need_cmd curl
need_cmd ping
need_cmd grep

if [[ $EUID -ne 0 ]]; then
    log_error "Запустите с sudo (нужен service.sh run / kill)"
    exit 1
fi

if [[ ! -x "$SERVICE_SCRIPT" ]]; then
    log_error "Не найден: $SERVICE_SCRIPT"
    exit 1
fi

if [[ ! -d "$REPO_DIR" ]] || [[ ! -f "$SCRIPT_DIR/nfqws" ]]; then
    log_info "Загрузка зависимостей..."
    "$SERVICE_SCRIPT" download-deps --default
fi

TARGET_NAMES=()
TARGET_URLS=()
TARGET_PING=()

if [[ "$TARGETS_MODE" == "custom" && -n "$CUSTOM_TARGETS_FILE" ]]; then
    load_targets_file "$CUSTOM_TARGETS_FILE" || log_warn "Не удалось прочитать $CUSTOM_TARGETS_FILE"
elif [[ "$TARGETS_MODE" == "essential" ]]; then
    if load_essential_targets_file "$TARGETS_FILE"; then
        log_info "Основные цели из $TARGETS_FILE"
    else
        log_warn "targets.txt не найден, встроенные основные цели"
        load_default_essential_targets
    fi
elif load_targets_file "$TARGETS_FILE"; then
    log_info "Цели из $TARGETS_FILE"
else
    log_warn "targets.txt не найден, встроенные цели по умолчанию"
    load_default_targets
fi

$USE_FROM_LISTS && load_from_lists

dedupe_targets
compute_max_name_len

if [[ ${#TARGET_NAMES[@]} -eq 0 ]]; then
    log_error "Нет целей для проверки"
    exit 1
fi

load_strategies
if [[ ${#STRATEGIES[@]} -eq 0 ]]; then
    log_error "Стратегии не найдены"
    exit 1
fi

init_analytics

trap 'stop_zapret; ipset_restore' EXIT INT TERM

$IPSET_ANY && ipset_switch_any

echo ""
echo -e "${BOLD}============================================================${NC}"
echo -e "${BOLD} ZAPRET STRATEGY TESTS (Linux / Flowseal Standard)${NC}"
echo -e "${BOLD} Strategies: ${#STRATEGIES[@]}  |  Targets: ${#TARGET_NAMES[@]}${NC}"
echo -e "${BOLD}============================================================${NC}"
log_warn "Отключите VPN и другие обходы."

stop_zapret

n=0
for strategy in "${STRATEGIES[@]}"; do
    n=$((n + 1))
    echo ""
    echo -e "${CYAN}------------------------------------------------------------${NC}"
    echo -e "${YELLOW} [$n/${#STRATEGIES[@]}] $strategy${NC}"
    echo -e "${CYAN}------------------------------------------------------------${NC}"
    run_tests_for_strategy "$strategy" || true

    a_ok=${ANALYTICS_OK[$strategy]:-0}
    a_err=${ANALYTICS_ERR[$strategy]:-0}
    echo -e "  ${DIM}Итог:${NC} OK ${GREEN}$a_ok${NC}  |  ERR ${RED}$a_err${NC}"
done

print_analytics
}

run_test_strategies_entry() {
    if [[ "${1:-}" == "--interactive" || "${1:-}" == "-i" ]]; then
        run_test_interactive_menu
        return $?
    fi
    reset_test_settings
    parse_test_cli_args "$@"
    run_strategy_tests_main
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_test_strategies_entry "$@"
fi
