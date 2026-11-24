#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# Модульные тесты функций из src/lib (без root и без сети)
# =============================================================================

BASE_DIR="$(realpath "$(dirname "$0")/..")"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

FAILED=0

# Каталог со стратегиями для тестов (имена как в Flowseal)
REPO_DIR="$TMP_DIR/zapret-latest"
CUSTOM_STRATEGIES_DIR="$TMP_DIR/custom-strategies"
CONF_FILE="$TMP_DIR/conf.env"
mkdir -p "$REPO_DIR" "$CUSTOM_STRATEGIES_DIR"

touch \
    "$REPO_DIR/general.bat" \
    "$REPO_DIR/general (ALT).bat" \
    "$REPO_DIR/general (SIMPLE FAKE).bat" \
    "$CUSTOM_STRATEGIES_DIR/general_nix1.bat"

source "$BASE_DIR/src/lib/common.sh"

# assert_normalize <входное имя> <ожидаемое имя стратегии>
assert_normalize() {
    local input="$1"
    local expected="$2"
    local actual

    if actual=$(normalize_strategy "$input"); then
        if [[ "$actual" == "$expected" ]]; then
            echo -e "${GREEN}[OK]${NC} normalize_strategy '$input' -> '$actual'"
            return 0
        fi
        echo -e "${RED}[FAIL]${NC} normalize_strategy '$input' -> '$actual', ожидалось '$expected'"
    else
        echo -e "${RED}[FAIL]${NC} normalize_strategy '$input' ничего не нашла, ожидалось '$expected'"
    fi
    FAILED=$((FAILED + 1))
}

# assert_not_found <входное имя>
assert_not_found() {
    local input="$1"

    if normalize_strategy "$input" >/dev/null; then
        echo -e "${RED}[FAIL]${NC} normalize_strategy '$input' нашла стратегию, хотя не должна"
        FAILED=$((FAILED + 1))
        return 0
    fi
    echo -e "${GREEN}[OK]${NC} normalize_strategy '$input' -> не найдено"
}

assert_normalize "general" "general.bat"
assert_normalize "general.bat" "general.bat"
assert_normalize "general (ALT)" "general (ALT).bat"
assert_normalize "general (ALT).bat" "general (ALT).bat"
assert_normalize "general (SIMPLE FAKE).bat" "general (SIMPLE FAKE).bat"
assert_normalize "GENERAL (ALT)" "general (ALT).bat"
assert_normalize "nix1" "general_nix1.bat"
assert_not_found "general (NOPE).bat"
assert_not_found "generl"

if [[ $FAILED -ne 0 ]]; then
    echo -e "\n${RED}Провалено тестов: $FAILED${NC}"
    exit 1
fi

echo -e "\n${GREEN}Все модульные тесты пройдены${NC}"
