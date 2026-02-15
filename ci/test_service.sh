#!/usr/bin/env bash

set -e

# =============================================================================
# CI E2E тест: проверка install/remove/start/stop сервиса
# =============================================================================

BASE_DIR="$(realpath "$(dirname "$0")/..")"

# Импортируем только константы
source "$BASE_DIR/lib/constants.sh"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TEST_PASSED=true

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

# Проверка что nfqws запущен
check_nfqws_running() {
    pgrep -f "nfqws" >/dev/null 2>&1
}

# Проверка что nftables правила существуют
check_nft_rules_exist() {
    if sudo nft list tables 2>/dev/null | grep -q "zapretunix"; then
        sudo nft list chain $NFT_TABLE $NFT_CHAIN 2>/dev/null | grep -q "$NFT_RULE_COMMENT"
        return $?
    fi
    return 1
}

# Очистка
cleanup() {
    print_status info "Финальная очистка..."
    "$BASE_DIR/service.sh" --remove 2>/dev/null || true
    sudo pkill -f nfqws 2>/dev/null || true
    "$BASE_DIR/stop_and_clean_nft.sh" >/dev/null 2>&1 || true
}

# Создать тестовый конфиг
create_test_config() {
    local strategy="$1"
    cat > "$BASE_DIR/conf.env" <<EOF
interface=any
gamefilter=false
strategy=$strategy
EOF
}

# -----------------------------------------------------------------------------
# Тесты
# -----------------------------------------------------------------------------

test_install() {
    print_status info "Тест: установка сервиса..."

    "$BASE_DIR/service.sh" --install
    sleep 2

    # Проверяем статус
    if "$BASE_DIR/service.sh" --status 2>&1 | grep -q "активен"; then
        print_status ok "Сервис установлен и активен"
    else
        print_status fail "Сервис не активен после установки"
        TEST_PASSED=false
        return 1
    fi

    # Проверяем nfqws
    if check_nfqws_running; then
        print_status ok "nfqws запущен"
    else
        print_status fail "nfqws не запущен"
        TEST_PASSED=false
        return 1
    fi

    # Проверяем nftables
    if check_nft_rules_exist; then
        print_status ok "nftables правила созданы"
    else
        print_status fail "nftables правила не созданы"
        TEST_PASSED=false
        return 1
    fi
}

test_stop() {
    print_status info "Тест: остановка сервиса..."

    "$BASE_DIR/service.sh" --stop
    sleep 1

    # Проверяем статус
    if "$BASE_DIR/service.sh" --status 2>&1 | grep -q "не активен"; then
        print_status ok "Сервис остановлен"
    else
        print_status fail "Сервис всё ещё активен"
        TEST_PASSED=false
        return 1
    fi

    # Проверяем nfqws
    if ! check_nfqws_running; then
        print_status ok "nfqws остановлен"
    else
        print_status fail "nfqws всё ещё запущен"
        TEST_PASSED=false
        return 1
    fi
}

test_start() {
    print_status info "Тест: запуск сервиса..."

    "$BASE_DIR/service.sh" --start
    sleep 2

    # Проверяем статус
    if "$BASE_DIR/service.sh" --status 2>&1 | grep -q "активен"; then
        print_status ok "Сервис запущен"
    else
        print_status fail "Сервис не запустился"
        TEST_PASSED=false
        return 1
    fi

    # Проверяем nfqws
    if check_nfqws_running; then
        print_status ok "nfqws запущен"
    else
        print_status fail "nfqws не запущен"
        TEST_PASSED=false
        return 1
    fi
}

test_restart() {
    print_status info "Тест: перезапуск сервиса..."

    "$BASE_DIR/service.sh" --restart
    sleep 2

    # Проверяем статус
    if "$BASE_DIR/service.sh" --status 2>&1 | grep -q "активен"; then
        print_status ok "Сервис перезапущен"
    else
        print_status fail "Сервис не активен после перезапуска"
        TEST_PASSED=false
        return 1
    fi

    # Проверяем nfqws
    if check_nfqws_running; then
        print_status ok "nfqws запущен"
    else
        print_status fail "nfqws не запущен"
        TEST_PASSED=false
        return 1
    fi
}

test_remove() {
    print_status info "Тест: удаление сервиса..."

    "$BASE_DIR/service.sh" --remove
    sleep 1

    # Проверяем статус
    if "$BASE_DIR/service.sh" --status 2>&1 | grep -q "не установлен"; then
        print_status ok "Сервис удалён"
    else
        print_status fail "Сервис всё ещё установлен"
        TEST_PASSED=false
        return 1
    fi

    # Проверяем nfqws
    if ! check_nfqws_running; then
        print_status ok "nfqws остановлен"
    else
        print_status fail "nfqws всё ещё запущен"
        TEST_PASSED=false
        return 1
    fi

    # Проверяем nftables
    if ! check_nft_rules_exist; then
        print_status ok "nftables правила очищены"
    else
        print_status fail "nftables правила всё ещё существуют"
        TEST_PASSED=false
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Основная логика
# -----------------------------------------------------------------------------

main() {
    echo "=============================================="
    echo "CI E2E тест сервиса"
    echo "=============================================="

    # Определяем init систему
    local init_sys
    init_sys=$("$BASE_DIR/service.sh" --help 2>&1 | head -1 || echo "unknown")
    print_status info "Init система: $(cat /proc/1/comm 2>/dev/null || echo 'unknown')"

    # Проверяем sudo
    if ! sudo -n true 2>/dev/null; then
        echo "Требуются права sudo для запуска тестов"
        exit 1
    fi

    # Скачиваем стратегии
    print_status info "Загрузка стратегий..."
    "$BASE_DIR/service.sh" --download

    # Получаем первую стратегию для теста
    local strategy
    strategy=$("$BASE_DIR/service.sh" --strategies | grep -E '\.bat$' | head -1)

    if [ -z "$strategy" ]; then
        print_status fail "Стратегии не найдены!"
        exit 1
    fi

    print_status info "Тестовая стратегия: $strategy"

    # Создаём конфиг
    create_test_config "$strategy"

    # Начальная очистка
    cleanup

    # Запускаем тесты последовательно
    echo ""
    test_install || true
    echo ""
    test_stop || true
    echo ""
    test_start || true
    echo ""
    test_restart || true
    echo ""
    test_remove || true

    # Итог
    echo ""
    echo "=============================================="
    if $TEST_PASSED; then
        print_status ok "Все тесты пройдены!"
        exit 0
    else
        print_status fail "Некоторые тесты провалены!"
        exit 1
    fi
}

trap cleanup EXIT

main "$@"
