#!/usr/bin/env bash

set -e

# =============================================================================
# CI E2E тест: проверка запуска всех стратегий
# Не использует внутренние функции - только CLI интерфейс
# =============================================================================

BASE_DIR="$(realpath "$(dirname "$0")/..")"

# Импортируем только константы
source "$BASE_DIR/lib/constants.sh"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED_STRATEGIES=()
PASSED_STRATEGIES=()

# -----------------------------------------------------------------------------
# Вспомогательные функции
# -----------------------------------------------------------------------------

print_status() {
    local status="$1"
    local message="$2"
    case "$status" in
        ok)   echo -e "${GREEN}[OK]${NC} $message" ;;
        fail) echo -e "${RED}[FAIL]${NC} $message" ;;
        info) echo -e "${YELLOW}[INFO]${NC} $message" ;;
    esac
}

# Проверка что nfqws НЕ запущен
check_nfqws_not_running() {
    if pgrep -f "nfqws" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Проверка что nfqws запущен
check_nfqws_running() {
    if pgrep -f "nfqws" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Проверка что nftables правила НЕ существуют
check_nft_rules_not_exist() {
    if sudo nft list tables 2>/dev/null | grep -q "zapretunix"; then
        return 1
    fi
    return 0
}

# Проверка что nftables правила существуют
check_nft_rules_exist() {
    if sudo nft list tables 2>/dev/null | grep -q "zapretunix"; then
        if sudo nft list chain $NFT_TABLE $NFT_CHAIN 2>/dev/null | grep -q "$NFT_RULE_COMMENT"; then
            return 0
        fi
    fi
    return 1
}

# Очистка после теста
cleanup() {
    print_status info "Очистка..."
    sudo pkill -f nfqws 2>/dev/null || true
    "$BASE_DIR/stop_and_clean_nft.sh" >/dev/null 2>&1 || true
}

# Получить список стратегий через CLI (вызывать после --download)
get_strategies_cli() {
    "$BASE_DIR/service.sh" --strategies | grep -E '\.bat$' || true
}

# -----------------------------------------------------------------------------
# Тест одной стратегии
# -----------------------------------------------------------------------------

test_strategy() {
    local strategy="$1"
    local test_passed=true

    echo ""
    echo "=========================================="
    echo "Тестирование стратегии: $strategy"
    echo "=========================================="

    # 1. Проверка начального состояния
    print_status info "Проверка начального состояния..."

    if ! check_nfqws_not_running; then
        print_status fail "nfqws уже запущен перед тестом"
        cleanup
    fi

    if ! check_nft_rules_not_exist; then
        print_status fail "nftables правила уже существуют перед тестом"
        cleanup
    fi

    # 2. Создаём временный конфиг
    local tmp_conf=$(mktemp)
    cat > "$tmp_conf" <<EOF
interface=any
gamefilter=false
strategy=$strategy
EOF

    # 3. Запуск main_script в фоне
    print_status info "Запуск стратегии..."

    # Копируем конфиг в conf.env
    cp "$tmp_conf" "$BASE_DIR/conf.env"

    # Запускаем main_script
    (
        cd "$BASE_DIR"
        timeout 5 ./main_script.sh -nointeractive &
        PID=$!
        sleep 2
        kill $PID 2>/dev/null || true
    ) 2>&1 &
    local bg_pid=$!

    # Ждём немного чтобы процесс запустился
    sleep 2

    # 4. Проверка что nfqws запустился
    if check_nfqws_running; then
        print_status ok "nfqws запущен"
    else
        print_status fail "nfqws НЕ запущен"
        test_passed=false
    fi

    # 5. Проверка что nftables правила созданы
    if check_nft_rules_exist; then
        print_status ok "nftables правила созданы"
    else
        print_status fail "nftables правила НЕ созданы"
        test_passed=false
    fi

    # 6. Остановка
    print_status info "Остановка..."
    cleanup

    # Ждём завершения фонового процесса
    wait $bg_pid 2>/dev/null || true

    sleep 0.5

    # 7. Проверка что всё остановлено
    if check_nfqws_not_running; then
        print_status ok "nfqws остановлен"
    else
        print_status fail "nfqws всё ещё запущен после остановки"
        test_passed=false
        sudo pkill -9 -f nfqws 2>/dev/null || true
    fi

    if check_nft_rules_not_exist; then
        print_status ok "nftables правила очищены"
    else
        print_status fail "nftables правила всё ещё существуют"
        test_passed=false
        "$BASE_DIR/stop_and_clean_nft.sh" >/dev/null 2>&1 || true
    fi

    # Удаляем временный конфиг
    rm -f "$tmp_conf"

    # Результат
    if $test_passed; then
        print_status ok "Стратегия $strategy: PASSED"
        PASSED_STRATEGIES+=("$strategy")
        return 0
    else
        print_status fail "Стратегия $strategy: FAILED"
        FAILED_STRATEGIES+=("$strategy")
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Основная логика
# -----------------------------------------------------------------------------

main() {
    echo "=============================================="
    echo "CI E2E тест стратегий zapret-discord-youtube-linux"
    echo "=============================================="

    # Проверяем что мы root или можем sudo
    if ! sudo -n true 2>/dev/null; then
        echo "Требуются права sudo для запуска тестов"
        exit 1
    fi

    # Скачиваем стратегии через CLI
    print_status info "Загрузка стратегий..."
    "$BASE_DIR/service.sh" --download

    # Получаем список стратегий через CLI
    print_status info "Получение списка стратегий..."
    local strategies
    mapfile -t strategies < <(get_strategies_cli)

    if [ ${#strategies[@]} -eq 0 ]; then
        print_status fail "Стратегии не найдены!"
        exit 1
    fi

    print_status info "Найдено стратегий: ${#strategies[@]}"
    for s in "${strategies[@]}"; do
        echo "  - $s"
    done

    # Начальная очистка
    cleanup

    # Тестируем каждую стратегию
    for strategy in "${strategies[@]}"; do
        test_strategy "$strategy" || true
    done

    # Итоговый отчёт
    echo ""
    echo "=============================================="
    echo "ИТОГОВЫЙ ОТЧЁТ"
    echo "=============================================="
    echo ""
    echo -e "${GREEN}Успешно: ${#PASSED_STRATEGIES[@]}${NC}"
    for s in "${PASSED_STRATEGIES[@]}"; do
        echo "  - $s"
    done

    echo ""
    echo -e "${RED}Провалено: ${#FAILED_STRATEGIES[@]}${NC}"
    for s in "${FAILED_STRATEGIES[@]}"; do
        echo "  - $s"
    done

    echo ""

    # Выход с кодом ошибки если есть провалы
    if [ ${#FAILED_STRATEGIES[@]} -gt 0 ]; then
        exit 1
    fi

    print_status ok "Все тесты пройдены!"
    exit 0
}

# Обработка сигналов
trap cleanup EXIT

main "$@"
