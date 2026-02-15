#!/usr/bin/env bash

# =============================================================================
# Общие функции для всех скриптов zapret-discord-youtube-linux
# =============================================================================

# Подключаем константы если ещё не подключены
if [[ -z "$SERVICE_NAME" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/constants.sh"
fi

# Флаг отладки (можно переопределить в скрипте)
DEBUG=${DEBUG:-false}

# -----------------------------------------------------------------------------
# Логирование
# -----------------------------------------------------------------------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

debug_log() {
    if $DEBUG; then
        echo "[DEBUG] $1"
    fi
}

handle_error() {
    log "Ошибка: $1"
    exit 1
}

# -----------------------------------------------------------------------------
# Проверка зависимостей
# -----------------------------------------------------------------------------

check_dependencies() {
    local deps=("git" "nft" "grep" "sed")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            handle_error "Не установлена утилита $dep"
        fi
    done
}

# -----------------------------------------------------------------------------
# Работа с конфигурацией
# -----------------------------------------------------------------------------

# Проверка существования conf.env и обязательных полей
# Использование: if check_conf_file "$CONF_FILE"; then ...
check_conf_file() {
    local conf_file="${1:-$CONF_FILE}"

    if [[ ! -f "$conf_file" ]]; then
        return 1
    fi

    local required_fields=("interface" "gamefilter" "strategy")
    for field in "${required_fields[@]}"; do
        if ! grep -q "^${field}=[^[:space:]]" "$conf_file"; then
            return 1
        fi
    done
    return 0
}

# Загрузка конфигурации из файла
load_config() {
    local conf_file="${1:-$CONF_FILE}"

    if [[ ! -f "$conf_file" ]]; then
        handle_error "Файл конфигурации $conf_file не найден"
    fi

    source "$conf_file"

    if [[ -z "$interface" ]] || [[ -z "$gamefilter" ]] || [[ -z "$strategy" ]]; then
        handle_error "Отсутствуют обязательные параметры в конфигурационном файле"
    fi
}

# -----------------------------------------------------------------------------
# Проверка статуса nfqws
# -----------------------------------------------------------------------------

check_nfqws_status() {
    if pgrep -f "nfqws" >/dev/null; then
        echo "Демоны nfqws запущены."
    else
        echo "Демоны nfqws не запущены."
    fi
}

# -----------------------------------------------------------------------------
# Работа со стратегиями
# -----------------------------------------------------------------------------

# Настройка репозитория со стратегиями
# Требует: REPO_DIR, REPO_URL, MAIN_REPO_REV, BASE_DIR
setup_repository() {
    if [ -d "$REPO_DIR" ]; then
        log "Использование существующей версии репозитория."
        return
    fi

    log "Клонирование репозитория..."
    git clone "$REPO_URL" "$REPO_DIR" || handle_error "Ошибка при клонировании репозитория"
    cd "$REPO_DIR" && git checkout "$MAIN_REPO_REV" && cd ..
    chmod +x "$BASE_DIR/rename_bat.sh"
    rm -rf "$REPO_DIR/.git"
    "$BASE_DIR/rename_bat.sh" || handle_error "Ошибка при переименовании файлов"
}

# Получение списка доступных стратегий (имена файлов)
# Требует: REPO_DIR, CUSTOM_STRATEGIES_DIR
get_strategies() {
    {
        # Кастомные стратегии
        if [ -d "$CUSTOM_STRATEGIES_DIR" ]; then
            find "$CUSTOM_STRATEGIES_DIR" -maxdepth 1 -type f -name "*.bat" -printf "%f\n" 2>/dev/null
        fi
        # Стратегии из репозитория
        if [ -d "$REPO_DIR" ]; then
            find "$REPO_DIR" -maxdepth 1 -type f \( -name "general*.bat" -o -name "discord*.bat" \) -printf "%f\n" 2>/dev/null
        fi
    } | sort -u
}

# Вывод списка стратегий
show_strategies() {
    echo "Доступные стратегии:"
    echo
    get_strategies
}

# Валидация и нормализация названия стратегии
# Возвращает 0 и выводит нормализованное имя, или 1 при ошибке
normalize_strategy() {
    local s="$1"

    # Поиск точного совпадения
    local exact_match
    exact_match=$(get_strategies | grep -E "^(${s}|${s}\\.bat|general_${s}|general_${s}\\.bat)$" | head -n1)

    if [ -n "$exact_match" ]; then
        echo "$exact_match"
        return 0
    fi

    # Регистронезависимый поиск
    local case_insensitive_match
    case_insensitive_match=$(get_strategies | grep -i -E "^(${s}|${s}\\.bat|general_${s}|general_${s}\\.bat)$" | head -n1)

    if [ -n "$case_insensitive_match" ]; then
        echo "$case_insensitive_match"
        return 0
    fi

    return 1
}

# Интерактивный выбор стратегии
# Записывает результат в переменную $selected_strategy
select_strategy_interactive() {
    local strategies_list
    mapfile -t strategies_list < <(get_strategies)

    if [ ${#strategies_list[@]} -eq 0 ]; then
        handle_error "Не найдены файлы стратегий .bat"
    fi

    echo "Доступные стратегии:"
    select selected_strategy in "${strategies_list[@]}"; do
        if [ -n "$selected_strategy" ]; then
            log "Выбрана стратегия: $selected_strategy"
            return 0
        fi
        echo "Неверный выбор. Попробуйте еще раз."
    done
}
