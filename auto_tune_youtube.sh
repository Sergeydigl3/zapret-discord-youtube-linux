#!/bin/bash

# ============================================================
# Auto Tune для zapret
# Автоматический подбор рабочей стратегии для YouTube
# ============================================================

# ═══════════════════════════════════════════════════════════
# КОНФИГУРАЦИЯ
# ═══════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT="$SCRIPT_DIR/main_script.sh"
STOP_SCRIPT="$SCRIPT_DIR/stop_and_clean_nft.sh"
REPO_DIR="$SCRIPT_DIR/zapret-latest"
CUSTOM_DIR="$SCRIPT_DIR/custom-strategies"
CONF_FILE="$SCRIPT_DIR/conf.env"
RESULTS_FILE="$SCRIPT_DIR/auto_tune_youtube_results.txt"

WAIT_TIME=2           # Пауза после запуска стратегии (сек)
CURL_TIMEOUT=3        # Таймаут curl (сек)
#MIN_RESPONSE_SIZE=1000 # Минимум байт для валидного ответа

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# ═══════════════════════════════════════════════════════════
# ДАННЫЕ
# ═══════════════════════════════════════════════════════════

declare -a STRATEGY_FILES=()      # Список файлов стратегий
declare -a WORKING_STRATEGIES=()  # Рабочие стратегии (номер:имя:yt_ok:cdn_ok)
TESTED_COUNT=0
SUCCESS_COUNT=0
FAILED_COUNT=0

# ═══════════════════════════════════════════════════════════
# ФУНКЦИИ: Работа со стратегиями
# ═══════════════════════════════════════════════════════════

# Загрузить список стратегий (порядок как в main_script.sh)
load_strategy_files() {
    # 1. Кастомные стратегии
    if [[ -d "$CUSTOM_DIR" ]]; then
        for file in "$CUSTOM_DIR"/*.bat; do
            [[ -f "$file" ]] && STRATEGY_FILES+=("$(basename "$file")")
        done
    fi
    # 2. Стандартные из репозитория
    if [[ -d "$REPO_DIR" ]]; then
        while IFS= read -r -d '' file; do
            STRATEGY_FILES+=("$(basename "$file")")
        done < <(find "$REPO_DIR" -maxdepth 1 -type f \( -name "general*.bat" -o -name "discord.bat" \) -print0)
    fi
}

# Получить имя стратегии по номеру (1-based)
get_strategy_name() {
    local idx=$(($1 - 1))
    [[ $idx -ge 0 && $idx -lt ${#STRATEGY_FILES[@]} ]] && echo "${STRATEGY_FILES[$idx]}"
}

# Извлечь номер из записи (формат: номер:имя:yt_ok:cdn_ok)
get_num_from_entry() {
    echo "${1%%:*}"
}

# Извлечь имя из записи
get_name_from_entry() {
    local rest="${1#*:}"
    echo "${rest%%:*}"
}

# ═══════════════════════════════════════════════════════════
# ФУНКЦИИ: Управление zapret
# ═══════════════════════════════════════════════════════════

stop_zapret() {
    sudo "$STOP_SCRIPT" 2>/dev/null
    sleep 1
}

run_strategy() {
    local num=$1
    # Передаём: y (подтверждение), номер стратегии, 1 (any интерфейс)
    printf "y\n%d\n1\n" "$num" | "$MAIN_SCRIPT" &
    sleep "$WAIT_TIME"
}

# Запустить main с стратегией (не в фоне, для постоянного использования)
launch_main_script() {
    local num=$1
    printf "y\n%d\n1\n" "$num" | "$MAIN_SCRIPT"
}

# ═══════════════════════════════════════════════════════════
# ФУНКЦИИ: Проверка YouTube
# ═══════════════════════════════════════════════════════════

# Проверка главной страницы (HTTP код + размер + ключевое слово)
check_youtube_main() {
    local tmpfile=$(mktemp)
    local code=$(curl -s --tlsv1.3 --connect-timeout "$CURL_TIMEOUT" --max-time "$CURL_TIMEOUT" \
        -o "$tmpfile" -w "%{http_code}" "https://www.youtube.com" 2>/dev/null)
    local size=$(wc -c < "$tmpfile" 2>/dev/null || echo 0)
    local has_keyword=0
    grep -qi "youtube" "$tmpfile" 2>/dev/null && has_keyword=1
    rm -f "$tmpfile"
    
    [[ "$code" =~ ^[23] ]] && [[ $has_keyword -eq 1 ]]
}

# Проверка CDN (любой HTTP ответ = успех)
check_youtube_cdn() {
    local code=$(curl -s --tlsv1.3 --connect-timeout "$CURL_TIMEOUT" --max-time "$CURL_TIMEOUT" \
        -o /dev/null -w "%{http_code}" "https://redirector.googlevideo.com" 2>/dev/null)
    [[ "$code" != "000" ]]
}

# Полная проверка YouTube (с выводом)
check_youtube_full() {
    echo "Проверяем YouTube (TLS 1.3):"
    echo -n "  youtube.com... "
    if check_youtube_main; then
        echo "✓"
    else
        echo "✗"
        return 1
    fi
    echo -n "  googlevideo.com (CDN)... "
    if check_youtube_cdn; then
        echo "✓"
        return 0
    else
        echo "✗"
        return 1
    fi
}

# Тест стратегии, возвращает "yt_ok:cdn_ok"
test_strategy() {
    local yt_ok=0 cdn_ok=0
    if check_youtube_main; then
        yt_ok=1
        check_youtube_cdn && cdn_ok=1
    fi
    echo "$yt_ok:$cdn_ok"
}

# ═══════════════════════════════════════════════════════════
# ФУНКЦИИ: Результаты
# ═══════════════════════════════════════════════════════════

show_results() {
    local header="
╔════════════════════════════════════════════════════════════╗
║                    РЕЗУЛЬТАТЫ ТЕСТА                        ║
╚════════════════════════════════════════════════════════════╝

Дата: $(date '+%Y-%m-%d %H:%M:%S')
Протестировано: $TESTED_COUNT из ${#STRATEGY_FILES[@]}
Проверка: TCP (TLS 1.3)

✓ Работают:     $SUCCESS_COUNT
✗ Не работают:  $FAILED_COUNT
"
    echo "$header"
    echo "$header" > "$RESULTS_FILE"
    
    if [[ $SUCCESS_COUNT -eq 0 ]]; then
        echo "❌ Ни одна стратегия не сработала."
        echo "❌ Ни одна стратегия не сработала." >> "$RESULTS_FILE"
        return 1
    fi
    
    local table="
────────────────────────────────────────────────────────────────
Рабочие стратегии:
────────────────────────────────────────────────────────────────"
    echo "$table"
    echo "$table" >> "$RESULTS_FILE"
    
    printf "  %-4s %-40s %s\n" "№" "Стратегия" "Статус"
    printf "  %-4s %-40s %s\n" "№" "Стратегия" "Статус" >> "$RESULTS_FILE"
    echo "────────────────────────────────────────────────────────────────"
    echo "────────────────────────────────────────────────────────────────" >> "$RESULTS_FILE"
    
    for entry in "${WORKING_STRATEGIES[@]}"; do
        local num="${entry%%:*}"
        local rest="${entry#*:}"
        local name="${rest%%:*}"
        rest="${rest#*:}"
        local yt_ok="${rest%%:*}"
        local cdn_ok="${rest#*:}"
        
        local cdn_status=$([[ $cdn_ok -gt 0 ]] && echo '✓' || echo '✗')
        local line=$(printf "  [%-2s] %-40s YT:✓ CDN:%s" "$num" "$name" "$cdn_status")
        echo "$line"
        echo "$line" >> "$RESULTS_FILE"
    done
    
    echo "────────────────────────────────────────────────────────────────"
    echo "────────────────────────────────────────────────────────────────" >> "$RESULTS_FILE"
    echo "Если стратегия не работает - попробуйте запустить stop_and_clean_nft.sh, а затем запустить стратегию снова" >> "$RESULTS_FILE"

    echo ""
    echo "Результаты сохранены в: $RESULTS_FILE"
}

# Сохранить стратегию в conf.env
save_strategy() {
    local name=$1
    [[ -z "$name" ]] && return 1
    
    cat > "$CONF_FILE" << EOF
interface=any
gamefilter=false
strategy=$name
EOF
    echo -e "${GREEN}✓${NC} Сохранено: strategy=$name"
    echo "  Запуск: ./main_script.sh -nointeractive"
}

# ═══════════════════════════════════════════════════════════
# ОСНОВНАЯ ЛОГИКА
# ═══════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║${NC}     ${BOLD}🔧 Auto Tune для zapret-youtube${NC}                        ${BOLD}${CYAN}║${NC}"
echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Загружаем стратегии
load_strategy_files
MAX_STRATEGY=${#STRATEGY_FILES[@]}

echo -e "  📋 Найдено стратегий: ${BOLD}$MAX_STRATEGY${NC}"
echo ""

# Проверки
if ! command -v curl &>/dev/null; then
    echo "❌ curl не установлен. Установите: sudo apt install curl"
    exit 1
fi
if [[ ! -f "$MAIN_SCRIPT" ]]; then
    echo "❌ main_script.sh не найден"
    exit 1
fi
if [[ $MAX_STRATEGY -eq 0 ]]; then
    echo "❌ Стратегии не найдены"
    exit 1
fi

# Проверка без zapret
echo "Проверяем доступность YouTube без zapret..."
if check_youtube_full; then
    echo ""
    echo -e "${GREEN}✓${NC} YouTube уже доступен. Ничего делать не нужно."
    exit 0
fi

        echo ""
echo "YouTube недоступен. Тестируем стратегии..."
echo ""

stop_zapret

# ═══════════════════════════════════════════════════════════
# ТЕСТИРОВАНИЕ
# ═══════════════════════════════════════════════════════════

for ((i=1; i<=MAX_STRATEGY; i++)); do
    name=$(get_strategy_name $i)
    printf "  ${BOLD}[%2d/%d]${NC} %-40s " "$i" "$MAX_STRATEGY" "$name"
        
    run_strategy $i >/dev/null 2>&1
    ((TESTED_COUNT++))
    
    result=$(test_strategy)
    yt_ok="${result%%:*}"
    cdn_ok="${result#*:}"
    
    if [[ $yt_ok -gt 0 ]]; then
        if [[ $cdn_ok -gt 0 ]]; then
            echo -e "${GREEN}YT:✓ CDN:✓${NC}"
        else
            echo -e "${GREEN}YT:✓${NC} ${RED}CDN:✗${NC}"
        fi
        ((SUCCESS_COUNT++))
        WORKING_STRATEGIES+=("$i:$name:$yt_ok:$cdn_ok")
    else
        echo -e "${RED}YT:✗${NC}"
        ((FAILED_COUNT++))
    fi
    
    stop_zapret >/dev/null 2>&1
done

            echo ""
echo -e "${GREEN}Завершено!${NC}"
            echo ""

# ═══════════════════════════════════════════════════════════
# РЕЗУЛЬТАТЫ
# ═══════════════════════════════════════════════════════════

show_results

if [[ $SUCCESS_COUNT -gt 0 ]]; then
    echo ""
    echo -e "${BOLD}s${NC} + номер - сохранить в conf.env"
    echo -e "номер - запустить main с выбранной стратегией"
    echo -e "Enter - выход"
    echo ""
    read -p "> " input
    
    if [[ -z "$input" ]]; then
        # Enter - просто выходим
        :
    elif [[ "$input" =~ ^[sS]([0-9]+)$ ]]; then
        # s + номер - сохранить в conf.env
        num="${BASH_REMATCH[1]}"
        found=false
        for entry in "${WORKING_STRATEGIES[@]}"; do
            entry_num=$(get_num_from_entry "$entry")
            if [[ "$entry_num" == "$num" ]]; then
                name=$(get_name_from_entry "$entry")
                save_strategy "$name"
                found=true
                break
            fi
        done
        if [[ "$found" == false ]]; then
            echo "❌ Стратегия #$num не найдена среди рабочих"
        fi
    elif [[ "$input" =~ ^[0-9]+$ ]]; then
        # Просто число - запустить main с этой стратегией
        num="$input"
        found=false
        for entry in "${WORKING_STRATEGIES[@]}"; do
            entry_num=$(get_num_from_entry "$entry")
            if [[ "$entry_num" == "$num" ]]; then
                name=$(get_name_from_entry "$entry")
                echo ""
                echo "🚀 Запускаем стратегию [$num] $name..."
                stop_zapret >/dev/null 2>&1
                launch_main_script "$num"
                found=true
                break
            fi
        done
        if [[ "$found" == false ]]; then
            echo "❌ Стратегия #$num не найдена среди рабочих"
        fi
    else
        echo "❌ Неверный ввод"
    fi
fi

echo ""
