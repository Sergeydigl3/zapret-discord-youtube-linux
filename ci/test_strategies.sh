#!/usr/bin/env bash

set -e

# =============================================================================
# CI E2E тест: проверка запуска всех стратегий
# Не использует внутренние функции - только CLI интерфейс
# =============================================================================

BASE_DIR="$(realpath "$(dirname "$0")/..")"

# Ожидаемые значения для проверки
EXPECTED_NFT_TABLE="inet zapretunix"
EXPECTED_NFT_CHAIN="output"
EXPECTED_NFT_COMMENT="Added by zapret script"

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
    if sudo nft list tables 2>/dev/null | grep -q "$EXPECTED_NFT_TABLE"; then
        return 1
    fi
    return 0
}

# Проверка что nftables правила существуют
check_nft_rules_exist() {
    if sudo nft list tables 2>/dev/null | grep -q "$EXPECTED_NFT_TABLE"; then
        if sudo nft list chain "$EXPECTED_NFT_TABLE" "$EXPECTED_NFT_CHAIN" 2>/dev/null | grep -q "$EXPECTED_NFT_COMMENT"; then
            return 0
        fi
    fi
    return 1
}

# Очистка после теста
cleanup() {
    print_status info "Очистка..."
    sudo pkill -f nfqws 2>/dev/null || true
    "$BASE_DIR/service.sh" kill >/dev/null 2>&1 || true
}

# Получить список стратегий через CLI (вызывать после download-deps)
get_strategies_cli() {
    "$BASE_DIR/service.sh" strategy list | grep -E '\.bat$' || true
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
    local tmp_conf
    tmp_conf=$(mktemp --suffix=.env)
    cat > "$tmp_conf" <<EOF
interface=any
gamefilter=false
strategy=$strategy
EOF

    # 3. Запуск через service.sh run в фоне
    print_status info "Запуск стратегии..."

    # Запускаем в фоне и мониторим вывод
    local log_file
    log_file=$(mktemp)
    (cd "$BASE_DIR" && timeout 10 ./service.sh run --config "$tmp_conf" > "$log_file" 2>&1) &
    local run_pid=$!

    # Ждём сообщения "Настройка успешно завершена" с tail (без polling)
    timeout 5 tail -f "$log_file" 2>/dev/null | grep -q "Настройка успешно завершена" || true

    # 4. Проверка что nfqws запустился
    if check_nfqws_running; then
        print_status ok "nfqws запущен"
    else
        print_status fail "nfqws НЕ запущен"
        echo "--- Лог запуска ---"
        cat "$log_file"
        echo "-------------------"
        test_passed=false
    fi

    # 5. Проверка что nftables правила созданы
    if check_nft_rules_exist; then
        print_status ok "nftables правила созданы"
    else
        print_status fail "nftables правила НЕ созданы"
        echo "--- Лог запуска ---"
        cat "$log_file"
        echo "-------------------"
        test_passed=false
    fi

    # 6. Остановка
    print_status info "Остановка..."
    kill $run_pid 2>/dev/null || true
    wait $run_pid 2>/dev/null || true
    cleanup
    rm -f "$log_file"

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

    # Проверяем, загружены ли уже зависимости
    if [[ ! -d "$BASE_DIR/zapret-latest" ]] || [[ ! -f "$BASE_DIR/nfqws" ]]; then
        # Скачиваем зависимости через CLI
        print_status info "Загрузка зависимостей (nfqws + стратегии)..."
        "$BASE_DIR/service.sh" download-deps --default
    else
        print_status info "Зависимости уже загружены, пропускаем загрузку..."
    fi

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
