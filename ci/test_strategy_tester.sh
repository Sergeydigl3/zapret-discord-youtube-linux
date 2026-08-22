#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# CI smoke test: проверка пользовательского test_strategies.sh
# =============================================================================

BASE_DIR="$(realpath "$(dirname "$0")/..")"
TEST_SCRIPT="$BASE_DIR/test_strategies.sh"

print_status() {
    local status="$1"
    local message="$2"
    case "$status" in
        ok)   echo "[OK] $message" ;;
        fail) echo "[FAIL] $message" ;;
        info) echo "[INFO] $message" ;;
    esac
}

cleanup() {
    "$BASE_DIR/service.sh" kill >/dev/null 2>&1 || true
}

main() {
    echo "=============================================="
    echo "CI smoke test test_strategies.sh"
    echo "=============================================="

    if [[ ! -f "$TEST_SCRIPT" ]]; then
        print_status fail "Не найден $TEST_SCRIPT"
        exit 1
    fi
    print_status ok "test_strategies.sh найден"

    print_status info "Проверка --help"
    "$TEST_SCRIPT" --help >/dev/null
    print_status ok "--help отрабатывает"

    print_status info "Проверка syntax"
    bash -n "$TEST_SCRIPT"
    print_status ok "syntax OK"

    # Первая доступная стратегия для короткого smoke run
    local strategy
    strategy="$("$BASE_DIR/service.sh" strategy list | awk '/\.bat$/ {print; exit}')"
    if [[ -z "$strategy" ]]; then
        print_status fail "Не удалось получить ни одной стратегии"
        exit 1
    fi
    print_status info "Стратегия для smoke: $strategy"

    print_status info "Запуск короткого smoke run"
    # Быстрый и компактный прогон: essential + no-ping + 1 стратегия
    timeout 180 "$TEST_SCRIPT" --quick --essential --no-ping -s "$strategy" >/dev/null
    print_status ok "smoke run завершен"

    print_status ok "test_strategies.sh smoke test PASSED"
}

trap cleanup EXIT
main "$@"
