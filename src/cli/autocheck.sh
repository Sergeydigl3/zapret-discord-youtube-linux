#!/usr/bin/env bash

# =============================================================================
# CLI: Автопроверка конфигураций
# Аналог утилиты "Run Tests" (utils/test zapret.ps1) из Flowseal/zapret-discord-youtube
# Перебирает все стратегии и проверяет доступность целей из targets.txt
# =============================================================================

# Пути и настройки
AUTOCHECK_TARGETS_FILE="$HOME_DIR_PATH/targets.txt"
AUTOCHECK_RESULTS_FILE="$HOME_DIR_PATH/auto_check_results.txt"
AUTOCHECK_WAIT_TIME=3
AUTOCHECK_CURL_TIMEOUT=3
AUTOCHECK_MAX_TIMEOUT=5
AUTOCHECK_PING_COUNT=3
AUTOCHECK_PING_TIMEOUT=2
AUTOCHECK_MAX_PARALLEL=6

# Цвета (не переопределяем, если уже заданы другими модулями)
[[ -z "$RED" ]]    && RED='\033[0;31m'
[[ -z "$GREEN" ]]  && GREEN='\033[0;32m'
[[ -z "$YELLOW" ]] && YELLOW='\033[33m'
[[ -z "$CYAN" ]]   && CYAN='\033[0;36m'
[[ -z "$BLUE" ]]   && BLUE='\033[0;34m'
[[ -z "$NC" ]]     && NC='\033[0m'
[[ -z "$BOLD" ]]   && BOLD='\033[1m'

# Глобальные переменные
declare -a AC_TARGET_NAMES=()
declare -a AC_TARGET_URLS=()
declare -a AC_TARGET_PINGS=()
declare -a AC_STRATEGIES=()
declare -a AC_SELECTED=()
declare -A AC_OK=()
declare -A AC_ERR=()
declare -A AC_UNSUP=()
declare -A AC_PING_OK=()
AC_IPSET_SAVED=false
AC_SERVICE_WAS_ACTIVE=false
AC_RUN_PID=""
AC_BEST_STRATEGY=""

# Справка для autocheck
show_autocheck_usage() {
    echo "Usage: $(basename "$0") autocheck"
    echo
    echo "Автопроверка конфигураций (стратегий) против списка целей из targets.txt"
    echo "Аналог 'Run Tests' из репозитория Flowseal/zapret-discord-youtube"
    echo
    echo "Проверки: HTTP (HTTP/1.1), TLS 1.2, TLS 1.3 для URL-целей и ping для PING-целей"
}

# -----------------------------------------------------------------------------
# Работа с целями (targets.txt)
# -----------------------------------------------------------------------------

# Парсинг целей из stdin, заполняет AC_TARGET_NAMES/URLS/PINGS
# Формат: Имя = "https://host..."  или  Имя = "PING:1.2.3.4"
_ac_parse_targets() {
    local line
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*$ ]]; then
            local name="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            if [[ "$val" == PING:* ]]; then
                AC_TARGET_NAMES+=("$name")
                AC_TARGET_URLS+=("")
                AC_TARGET_PINGS+=("${val#PING:}")
            elif [[ -n "$val" ]]; then
                AC_TARGET_NAMES+=("$name")
                AC_TARGET_URLS+=("$val")
                AC_TARGET_PINGS+=("")
            fi
        fi
    done
}

# Встроенные цели по умолчанию
_ac_default_targets_text() {
    cat <<'EOF'
# targets.txt - список целей для автопроверки конфигураций
#
# Формат:
#   Имя = "https://host..."   -> проверки HTTP/TLS1.2/TLS1.3
#   Имя = "PING:1.2.3.4"      -> только ping
#
# Имя должно состоять из одного слова (буквы/цифры/подчёркивание).
# Можно добавлять и удалять строки.

### Discord
DiscordMain           = "https://discord.com"
DiscordGateway        = "https://gateway.discord.gg"
DiscordCDN            = "https://cdn.discordapp.com"
DiscordUpdates        = "https://updates.discord.com"

### YouTube
YouTubeWeb            = "https://www.youtube.com"
YouTubeShort          = "https://youtu.be"
YouTubeImage          = "https://i.ytimg.com"
YouTubeVideoRedirect  = "https://redirector.googlevideo.com"

### Google
GoogleMain            = "https://www.google.com"
GoogleGstatic         = "https://www.gstatic.com"

### Cloudflare
CloudflareWeb         = "https://www.cloudflare.com"
CloudflareCDN         = "https://cdnjs.cloudflare.com"

### Public DNS (только PING)
CloudflareDNS1111     = "PING:1.1.1.1"
CloudflareDNS1001     = "PING:1.0.0.1"
GoogleDNS8888         = "PING:8.8.8.8"
GoogleDNS8844         = "PING:8.8.4.4"
Quad9DNS9999          = "PING:9.9.9.9"
EOF
}

# Записать дефолтные цели в файл
_ac_write_default_targets() {
    _ac_default_targets_text > "$1"
}

# Загрузка целей из targets.txt (создаёт файл при первом запуске)
_ac_load_targets() {
    AC_TARGET_NAMES=()
    AC_TARGET_URLS=()
    AC_TARGET_PINGS=()

    if [[ ! -f "$AUTOCHECK_TARGETS_FILE" ]]; then
        _ac_write_default_targets "$AUTOCHECK_TARGETS_FILE"
        echo -e "${GREEN}Создан файл целей:${NC} $AUTOCHECK_TARGETS_FILE"
    fi

    _ac_parse_targets < "$AUTOCHECK_TARGETS_FILE"

    # Если файл пуст — используем встроенные цели по умолчанию
    if [[ ${#AC_TARGET_NAMES[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Файл целей пуст, используются встроенные цели.${NC}"
        _ac_default_targets_text | _ac_parse_targets
    fi
}

# -----------------------------------------------------------------------------
# Проверки (curl / ping)
# -----------------------------------------------------------------------------

# Проверка одного URL через curl, возвращает OK/SSL/UNSUP/ERR
# SSL  - похоже на DNS-подмену или проблему с сертификатом
# UNSUP- протокол/TLS не поддерживается
_ac_curl_status() {
    local url="$1"
    shift
    local errfile stderr_text exit_code
    errfile=$(mktemp)
    curl -s -I --connect-timeout "$AUTOCHECK_CURL_TIMEOUT" --max-time "$AUTOCHECK_MAX_TIMEOUT" \
        -o /dev/null "$@" "$url" 2>"$errfile"
    exit_code=$?
    stderr_text=$(cat "$errfile")
    rm -f "$errfile"

    if [[ $exit_code -eq 0 ]]; then
        echo "OK"
    elif echo "$stderr_text" | grep -qEi "could not resolve host|SSL certificate problem|self[- ]?signed|certificate verify failed|unable to get local issuer certificate"; then
        echo "SSL"
    elif [[ $exit_code -eq 35 ]] || echo "$stderr_text" | grep -qiE "does not support|not supported|unsupported protocol|TLS.*not supported|Unrecognized option|Unknown option|unsupported option"; then
        echo "UNSUP"
    else
        echo "ERR"
    fi
}

# Проверка ping хоста, возвращает "Ping: X ms" или "Ping: TIMEOUT"
_ac_ping_result() {
    local host="$1"
    local out avg
    out=$(ping -c "$AUTOCHECK_PING_COUNT" -W "$AUTOCHECK_PING_TIMEOUT" "$host" 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        avg=$(echo "$out" | grep -oP 'min/avg/max/mdev\s*=\s*\K[0-9.]+/[0-9.]+/[0-9.]+/[0-9.]+' | head -n1 | cut -d'/' -f2)
        if [[ -n "$avg" ]]; then
            echo "Ping: ${avg} ms"
        else
            echo "Ping: OK"
        fi
    else
        echo "Ping: TIMEOUT"
    fi
}

# Тест одной цели (запускается в фоне): пишет цветную строку в outfile
# и счётчики ok/err/unsup/ping_ok/ping_total в counterfile
_ac_test_target() {
    local idx="$1" outfile="$2" counterfile="$3"
    local name="${AC_TARGET_NAMES[$idx]}"
    local ok=0 err=0 unsup=0 ping_ok=0 ping_total=1

    {
        if [[ -n "${AC_TARGET_URLS[$idx]}" ]]; then
            local url="${AC_TARGET_URLS[$idx]}"
            local http tls12 tls13 s color
            http=$(_ac_curl_status "$url" --http1.1)
            tls12=$(_ac_curl_status "$url" --tlsv1.2 --tls-max 1.2)
            tls13=$(_ac_curl_status "$url" --tlsv1.3 --tls-max 1.3)

            for s in "$http" "$tls12" "$tls13"; do
                case "$s" in
                    OK)   ((ok++)) ;;
                    UNSUP) ((unsup++)) ;;
                    *)    ((err++)) ;;
                esac
            done

            printf "  %-26s " "$name"
            for s in "$http" "$tls12" "$tls13"; do
                case "$s" in
                    OK)    color="$GREEN" ;;
                    UNSUP) color="$YELLOW" ;;
                    *)     color="$RED" ;;
                esac
                printf "${color}%s${NC}  " "$s"
            done
            printf "\n"
        else
            local p
            p=$(_ac_ping_result "${AC_TARGET_PINGS[$idx]}")
            printf "  %-26s %s\n" "$name" "$p"
            if [[ "$p" == "Ping: TIMEOUT" ]]; then
                ping_ok=0
            else
                ping_ok=1
            fi
        fi
    } > "$outfile"

    printf "ok=%s err=%s unsup=%s ping_ok=%s ping_total=%s\n" "$ok" "$err" "$unsup" "$ping_ok" "$ping_total" > "$counterfile"
}

# -----------------------------------------------------------------------------
# Запуск/остановка стратегии
# -----------------------------------------------------------------------------

_ac_stop_zapret() {
    if [[ -n "$AC_RUN_PID" ]] && kill -0 "$AC_RUN_PID" 2>/dev/null; then
        kill "$AC_RUN_PID" 2>/dev/null
        wait "$AC_RUN_PID" 2>/dev/null
    fi
    AC_RUN_PID=""
    "$SERVICE_SCRIPT" kill >/dev/null 2>&1
    sleep 1
}

_ac_run_strategy() {
    local name="$1"
    "$SERVICE_SCRIPT" run -s "$name" -i any >/dev/null 2>&1 &
    AC_RUN_PID=$!
    sleep "$AUTOCHECK_WAIT_TIME"
    if ! pgrep -f nfqws >/dev/null 2>&1; then
        echo -e "${YELLOW}  Внимание: nfqws не запустился для этой стратегии${NC}"
    fi
}

# -----------------------------------------------------------------------------
# Работа с ipset (без интерактивных запросов)
# -----------------------------------------------------------------------------

_ac_ipset_save() {
    local ipset="$REPO_DIR/lists/ipset-all.txt"
    local bipset="$REPO_DIR/lists/ipset-all.txt.backup"
    if [[ -f "$ipset" ]]; then
        rm -f "$bipset"
        cp "$ipset" "$bipset"
    else
        touch "$ipset"
    fi
    AC_IPSET_SAVED=true
}

_ac_ipset_switch_any() {
    local ipset="$REPO_DIR/lists/ipset-all.txt"
    rm -f "$ipset"
    touch "$ipset"
    echo -e "Режим ipset переключён на ${YELLOW}'Any'${NC}"
}

_ac_ipset_restore() {
    local ipset="$REPO_DIR/lists/ipset-all.txt"
    local bipset="$REPO_DIR/lists/ipset-all.txt.backup"
    if [[ -f "$bipset" ]]; then
        rm -f "$ipset"
        cp "$bipset" "$ipset"
    fi
    AC_IPSET_SAVED=false
}

# -----------------------------------------------------------------------------
# Выбор конфигураций для теста
# -----------------------------------------------------------------------------

_ac_select_configs() {
    local -a all=("$@")
    local mode input part

    while true; do
        read -p "Режим тестирования: [1] Все конфигурации, [2] Выбранные: " mode
        case "$mode" in
            1|"")
                AC_SELECTED=("${all[@]}")
                return 0
                ;;
            2)
                while true; do
                    echo ""
                    echo "Доступные конфигурации:"
                    for ((i=0; i<${#all[@]}; i++)); do
                        printf "  [%2d] %s\n" "$((i+1))" "${all[$i]}"
                    done
                    echo ""
                    read -p "Введите номера (например 1,3,5 или 2-7; 0 — все): " input
                    if [[ -z "$input" || "$input" == "0" ]]; then
                        AC_SELECTED=("${all[@]}")
                        return 0
                    fi

                    local -A seen=()
                    local -a picked=()
                    local invalid=false

                    IFS=',' read -r -a parts <<< "$input"
                    for part in "${parts[@]}"; do
                        part="${part// /}"
                        if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                            local start="${BASH_REMATCH[1]}" end="${BASH_REMATCH[2]}"
                            if (( start > end )); then
                                invalid=true
                                continue
                            fi
                            if (( start < 1 )); then start=1; invalid=true; fi
                            if (( end > ${#all[@]} )); then end=${#all[@]}; invalid=true; fi
                            for ((n=start; n<=end; n++)); do
                                [[ -z "${seen[$n]}" ]] && { seen[$n]=1; picked+=("${all[$((n-1))]}"); }
                            done
                        elif [[ "$part" =~ ^[0-9]+$ ]]; then
                            local n=$((10#$part))
                            if (( n >= 1 && n <= ${#all[@]} )); then
                                [[ -z "${seen[$n]}" ]] && { seen[$n]=1; picked+=("${all[$((n-1))]}"); }
                            else
                                invalid=true
                            fi
                        else
                            invalid=true
                        fi
                    done

                    if [[ ${#picked[@]} -eq 0 ]]; then
                        echo -e "${YELLOW}Не выбрано ни одной конфигурации. Попробуйте ещё раз.${NC}"
                        continue
                    fi
                    if [[ "$invalid" == true ]]; then
                        echo -e "${YELLOW}Часть ввода пропущена (вне диапазона или неверный формат).${NC}"
                    fi
                    echo -e "${GREEN}Выбрано конфигураций: ${#picked[@]}${NC}"
                    AC_SELECTED=("${picked[@]}")
                    return 0
                done
                ;;
            *)
                echo -e "${YELLOW}Неверный ввод.${NC}"
                ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# Восстановление состояния (трап и завершение)
# -----------------------------------------------------------------------------

_ac_cleanup() {
    echo ""
    echo -e "${YELLOW}Восстановление состояния...${NC}"
    _ac_stop_zapret
    if [[ "$AC_IPSET_SAVED" == true ]]; then
        _ac_ipset_restore
        echo "Режим ipset восстановлен."
    fi
    if [[ "$AC_SERVICE_WAS_ACTIVE" == true ]]; then
        echo "Перезапуск сервиса zapret..."
        start_service >/dev/null 2>&1 || true
    fi
}

# -----------------------------------------------------------------------------
# Аналитика и сохранение результатов
# -----------------------------------------------------------------------------

_ac_show_analytics() {
    local strategy best="" best_score=-1 best_ping=-1

    echo ""
    echo -e "${CYAN}══════════════════════════ АНАЛИТИКА ══════════════════════════${NC}"
    echo ""

    for strategy in "${AC_SELECTED[@]}"; do
        local ok="${AC_OK[$strategy]:-0}"
        local err="${AC_ERR[$strategy]:-0}"
        local unsup="${AC_UNSUP[$strategy]:-0}"
        local ping_ok="${AC_PING_OK[$strategy]:-0}"
        printf "  %-40s OK: %-3s ERR: %-3s UNSUP: %-3s Ping OK: %s\n" \
            "$strategy" "$ok" "$err" "$unsup" "$ping_ok"
        if (( ok > best_score )) || { (( ok == best_score )) && (( ping_ok > best_ping )); }; then
            best_score=$ok
            best_ping=$ping_ok
            best="$strategy"
        fi
    done

    AC_BEST_STRATEGY="$best"

    echo ""
    if [[ -n "$best" ]]; then
        echo -e "  ${GREEN}Лучшая стратегия: ${BOLD}$best${NC}"
    else
        echo -e "  ${RED}Ни одна стратегия не сработала.${NC}"
    fi

    {
        echo "=== АНАЛИТИКА ==="
        for strategy in "${AC_SELECTED[@]}"; do
            printf "%s : OK: %s, ERR: %s, UNSUP: %s, Ping OK: %s\n" \
                "$strategy" "${AC_OK[$strategy]:-0}" "${AC_ERR[$strategy]:-0}" \
                "${AC_UNSUP[$strategy]:-0}" "${AC_PING_OK[$strategy]:-0}"
        done
        echo ""
        echo "Лучшая стратегия: $best"
    } >> "$AUTOCHECK_RESULTS_FILE"

    echo ""
    echo -e "Результаты сохранены в: ${GREEN}$AUTOCHECK_RESULTS_FILE${NC}"
}

# -----------------------------------------------------------------------------
# Главная функция автопроверки
# -----------------------------------------------------------------------------

show_autocheck_menu() {
    # В автопроверке ошибки отдельных проверок ожидаемы — отключаем set -e
    local restore_errexit=false
    if [[ $- == *e* ]]; then
        restore_errexit=true
    fi
    set +e

    clear
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}         Автопроверка конфигураций (Run Tests)${NC}"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "Перебирает все стратегии и проверяет доступность целей из ${GREEN}targets.txt${NC}"
    echo -e "Проверки: ${BLUE}HTTP (HTTP/1.1), TLS 1.2, TLS 1.3${NC}, для PING-целей — ping"
    echo -e "На время проверки ipset переключается в режим ${YELLOW}'Any'${NC} и восстанавливается в конце"
    echo -e "Активный сервис zapret будет остановлен и ${GREEN}перезапущен${NC} в конце"
    echo ""

    if ! command -v curl >/dev/null 2>&1; then
        show_error "curl не установлен. Установите: sudo apt install curl"
        return 0
    fi

    # Загружаем стратегии
    mapfile -t AC_STRATEGIES < <(get_strategies)
    if [[ ${#AC_STRATEGIES[@]} -eq 0 ]]; then
        show_error "Стратегии не найдены. Запустите: ./service.sh download-deps --default"
        return 0
    fi

    # Загружаем цели
    _ac_load_targets
    if [[ ${#AC_TARGET_NAMES[@]} -eq 0 ]]; then
        show_error "Не удалось загрузить цели для проверки"
        return 0
    fi

    echo -e "Найдено конфигураций: ${BOLD}${#AC_STRATEGIES[@]}${NC}, целей: ${BOLD}${#AC_TARGET_NAMES[@]}${NC}"

    # Выбор конфигураций
    AC_SELECTED=()
    _ac_select_configs "${AC_STRATEGIES[@]}"
    if [[ ${#AC_SELECTED[@]} -eq 0 ]]; then
        return 0
    fi

    # Кэшируем привилегии, чтобы sudo не запрашивал пароль в фоновых запусках
    elevate_cache_credentials >/dev/null 2>&1 || true

    # Запоминаем, активен ли сервис
    _load_init_backend
    local svc_rc=0
    check_service_status >/dev/null 2>&1 || svc_rc=$?
    if [[ $svc_rc -eq 2 ]]; then
        AC_SERVICE_WAS_ACTIVE=true
    fi

    # Сохраняем ipset и переключаем в Any
    if [[ -d "$REPO_DIR/lists" ]]; then
        _ac_ipset_save
        _ac_ipset_switch_any
    else
        echo -e "${YELLOW}Текущая версия конфигураций не поддерживает смену режима ipset.${NC}"
    fi

    # Трап на случай прерывания
    trap '_ac_cleanup; exit 130' SIGINT

    echo ""
    echo -e "Тестируем ${BOLD}${#AC_SELECTED[@]}${NC} конфигураций. Это может занять несколько минут..."
    echo ""

    # Заголовок файла результатов
    {
        echo "Результаты автопроверки конфигураций"
        echo "Дата: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Протестировано конфигураций: ${#AC_SELECTED[@]}"
        echo "Целей: ${#AC_TARGET_NAMES[@]}"
        echo ""
    } > "$AUTOCHECK_RESULTS_FILE"

    local idx=0
    local strategy
    for strategy in "${AC_SELECTED[@]}"; do
        ((idx++))
        echo -e "${CYAN}──────────────────────────────────────────────────────────────${NC}"
        printf "${YELLOW}  [%d/%d] %s${NC}\n" "$idx" "${#AC_SELECTED[@]}" "$strategy"
        echo -e "${CYAN}──────────────────────────────────────────────────────────────${NC}"

        {
            echo "------------------------------------------------------------"
            echo "[$idx/${#AC_SELECTED[@]}] $strategy"
            echo "------------------------------------------------------------"
        } >> "$AUTOCHECK_RESULTS_FILE"

        _ac_stop_zapret
        _ac_run_strategy "$strategy"

        # Запускаем проверки целей с ограниченным параллелизмом
        local tmpdir counterdir
        tmpdir=$(mktemp -d)
        counterdir=$(mktemp -d)
        local -a jobs=()
        local t
        for ((t=0; t<${#AC_TARGET_NAMES[@]}; t++)); do
            local f="$tmpdir/$t.txt" c="$counterdir/$t.txt"
            _ac_test_target "$t" "$f" "$c" &
            jobs+=($!)
            if (( ${#jobs[@]} >= AUTOCHECK_MAX_PARALLEL )); then
                for j in "${jobs[@]}"; do wait "$j" 2>/dev/null; done
                jobs=()
            fi
        done
        for j in "${jobs[@]}"; do wait "$j" 2>/dev/null; done

        # Печатаем результаты и собираем статистику
        local ok=0 err=0 unsup=0 ping_ok=0 ping_total=0 tok c
        for ((t=0; t<${#AC_TARGET_NAMES[@]}; t++)); do
            cat "$tmpdir/$t.txt"
            sed $'s/\x1b\[[0-9;]*m//g' "$tmpdir/$t.txt" >> "$AUTOCHECK_RESULTS_FILE"
            if [[ -f "$counterdir/$t.txt" ]]; then
                c=$(cat "$counterdir/$t.txt")
                for tok in $c; do
                    case "$tok" in
                        ok=*)         ok=$((ok + ${tok#ok=})) ;;
                        err=*)        err=$((err + ${tok#err=})) ;;
                        unsup=*)      unsup=$((unsup + ${tok#unsup=})) ;;
                        ping_ok=*)    ping_ok=$((ping_ok + ${tok#ping_ok=})) ;;
                        ping_total=*) ping_total=$((ping_total + ${tok#ping_total=})) ;;
                    esac
                done
            fi
        done
        rm -rf "$tmpdir" "$counterdir"

        AC_OK[$strategy]=$ok
        AC_ERR[$strategy]=$err
        AC_UNSUP[$strategy]=$unsup
        AC_PING_OK[$strategy]=$ping_ok

        local status_color="$GREEN"
        if (( err > 0 )); then status_color="$RED"; fi
        printf "\n  ${status_color}OK: %s   ERR: %s   UNSUP: %s   Ping OK: %s${NC}\n\n" \
            "$ok" "$err" "$unsup" "$ping_ok"
        {
            printf "OK: %s, ERR: %s, UNSUP: %s, Ping OK: %s\n\n" "$ok" "$err" "$unsup" "$ping_ok"
        } >> "$AUTOCHECK_RESULTS_FILE"

        _ac_stop_zapret
    done

    trap - SIGINT

    _ac_show_analytics

    # Предложение сохранить лучшую стратегию
    if [[ -n "$AC_BEST_STRATEGY" ]]; then
        echo ""
        read -p "Сохранить лучшую стратегию в conf.env? [y/N]: " save_best
        if [[ "$save_best" =~ ^[Yy]$ ]]; then
            RESTART_SERVICE=false
            update_config "$AC_BEST_STRATEGY" any false false auto
            echo -e "${GREEN}Сохранено:${NC} strategy=$AC_BEST_STRATEGY"
        fi
    fi

    _ac_cleanup

    if [[ "$restore_errexit" == true ]]; then
        set -e
    fi

    read -p "Нажмите Enter для продолжения..."
    return 0
}

# Обработчик команды autocheck
handle_autocheck_command() {
    case "${1:-}" in
        -h|--help)
            show_autocheck_usage
            ;;
        "")
            show_autocheck_menu
            ;;
        *)
            echo "Unknown autocheck command: $1"
            show_autocheck_usage
            exit 1
            ;;
    esac
}
