#!/usr/bin/env bash

# =============================================================================
# Настройка прав доступа для работы без пароля (sudo/doas)
# =============================================================================

SUDOERS_FILE="/etc/sudoers.d/zapret"
DOAS_CONF="/etc/doas.conf"

# Получить путь к команде
get_cmd_path() {
    command -v "$1" 2>/dev/null || echo "/usr/bin/$1"
}

# -----------------------------------------------------------------------------
# Генерация sudoers
# -----------------------------------------------------------------------------

generate_sudoers_content() {
    local user="$1"
    local nfqws_path="${2:-$NFQWS_PATH}"
    local nft_path=$(get_cmd_path nft)
    local pkill_path=$(get_cmd_path pkill)

    cat <<EOF
# Zapret Discord YouTube - NOPASSWD для $user
# Файл: $SUDOERS_FILE

$user ALL=(root) NOPASSWD: $nft_path *
$user ALL=(root) NOPASSWD: $nfqws_path *
$user ALL=(root) NOPASSWD: $pkill_path -f nfqws
EOF
}

setup_sudoers() {
    local user="${1:-$USER}"

    echo "Настройка sudoers для $user..."

    # Проверяем директорию sudoers.d
    if [[ ! -d "/etc/sudoers.d" ]]; then
        echo "Ошибка: /etc/sudoers.d не существует"
        return 1
    fi

    local content
    content=$(generate_sudoers_content "$user" "$NFQWS_PATH")

    echo ""
    echo "Будет создан $SUDOERS_FILE:"
    echo "─────────────────────────────────────────"
    echo "$content"
    echo "─────────────────────────────────────────"
    echo ""

    read -p "Создать? [Y/n]: " confirm
    if [[ "${confirm:-Y}" =~ ^[Nn]$ ]]; then
        echo "Отменено"
        return 1
    fi

    echo "$content" | elevate tee "$SUDOERS_FILE" > /dev/null || {
        echo "Ошибка записи $SUDOERS_FILE"
        return 1
    }

    elevate chmod 440 "$SUDOERS_FILE"

    # Проверяем синтаксис
    if command -v visudo >/dev/null 2>&1; then
        if ! elevate visudo -c -f "$SUDOERS_FILE" 2>/dev/null; then
            echo "Ошибка синтаксиса! Удаляю файл..."
            elevate rm -f "$SUDOERS_FILE"
            return 1
        fi
    fi

    echo "Готово: $SUDOERS_FILE"
    return 0
}

# -----------------------------------------------------------------------------
# Генерация doas.conf
# -----------------------------------------------------------------------------

generate_doas_rules() {
    local user="$1"
    local nfqws_path="${2:-$NFQWS_PATH}"
    local nft_path=$(get_cmd_path nft)

    cat <<EOF
# Zapret Discord YouTube - nopass для $user
permit nopass $user as root cmd $nft_path
permit nopass $user as root cmd $nfqws_path
permit nopass $user as root cmd pkill args -f nfqws
EOF
}

setup_doas() {
    local user="${1:-$USER}"

    echo "Настройка doas для $user..."

    local rules
    rules=$(generate_doas_rules "$user" "$NFQWS_PATH")

    echo ""
    echo "Будут добавлены в $DOAS_CONF:"
    echo "─────────────────────────────────────────"
    echo "$rules"
    echo "─────────────────────────────────────────"
    echo ""

    read -p "Добавить? [Y/n]: " confirm
    if [[ "${confirm:-Y}" =~ ^[Nn]$ ]]; then
        echo "Отменено"
        return 1
    fi

    # Проверяем, есть ли уже наши правила
    if [[ -f "$DOAS_CONF" ]] && grep -q "# Zapret Discord YouTube" "$DOAS_CONF"; then
        echo "Правила уже есть в $DOAS_CONF"
        read -p "Заменить? [Y/n]: " replace
        if [[ "${replace:-Y}" =~ ^[Yy]$ ]]; then
            # Удаляем старый блок (от маркера до пустой строки или конца)
            elevate sed -i '/# Zapret Discord YouTube/,/^$/d' "$DOAS_CONF"
        else
            return 0
        fi
    fi

    # Добавляем правила
    {
        echo ""
        echo "$rules"
    } | elevate tee -a "$DOAS_CONF" > /dev/null || {
        echo "Ошибка записи в $DOAS_CONF"
        return 1
    }

    echo "Готово: правила добавлены в $DOAS_CONF"
    return 0
}

# -----------------------------------------------------------------------------
# Главные функции
# -----------------------------------------------------------------------------

setup_permissions() {
    local user="${1:-$USER}"
    local system
    system=$(get_elevate_cmd) || {
        echo "Ошибка: не найден sudo или doas"
        return 1
    }

    echo "Настройка NOPASSWD для $user..."
    echo ""

    case "$system" in
        sudo)
            setup_sudoers "$user"
            ;;
        doas)
            setup_doas "$user"
            ;;
    esac
}

remove_permissions() {
    local removed=false

    # Удаляем sudoers
    if [[ -f "$SUDOERS_FILE" ]]; then
        elevate rm -f "$SUDOERS_FILE"
        echo "Удалён $SUDOERS_FILE"
        removed=true
    fi

    # Удаляем правила из doas.conf
    if [[ -f "$DOAS_CONF" ]] && grep -q "# Zapret Discord YouTube" "$DOAS_CONF"; then
        elevate sed -i '/# Zapret Discord YouTube/,/^$/d' "$DOAS_CONF"
        echo "Удалены правила из $DOAS_CONF"
        removed=true
    fi

    if ! $removed; then
        echo "Настройки не найдены"
    fi
}

show_permissions_status() {
    local system
    system=$(get_elevate_cmd 2>/dev/null) || system="none"

    echo "Система: $system"
    echo ""

    # Sudoers
    if [[ -f "$SUDOERS_FILE" ]]; then
        echo "sudoers: $SUDOERS_FILE"
        echo "─────────────────────────────────────────"
        cat "$SUDOERS_FILE" 2>/dev/null || elevate cat "$SUDOERS_FILE"
        echo "─────────────────────────────────────────"
    else
        echo "sudoers: не настроен"
    fi

    echo ""

    # Doas
    if [[ -f "$DOAS_CONF" ]] && grep -q "# Zapret Discord YouTube" "$DOAS_CONF"; then
        echo "doas: настроен"
        echo "─────────────────────────────────────────"
        grep -A3 "# Zapret Discord YouTube" "$DOAS_CONF"
        echo "─────────────────────────────────────────"
    else
        echo "doas: не настроен"
    fi
}
