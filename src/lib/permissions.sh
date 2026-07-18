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

    local iptables_path=$(get_cmd_path iptables)
    local ip6tables_path=$(get_cmd_path ip6tables)

    cat <<EOF
# Zapret Discord YouTube - NOPASSWD для $user
# Файл: $SUDOERS_FILE

$user ALL=(root) NOPASSWD: $nft_path *
$user ALL=(root) NOPASSWD: $iptables_path *
$user ALL=(root) NOPASSWD: $ip6tables_path *
$user ALL=(root) NOPASSWD: $nfqws_path *
$user ALL=(root) NOPASSWD: $pkill_path -f nfqws
EOF
}

setup_sudoers() {
    local user="${1:-$USER}"

    if [[ -f /etc/os-release ]] && grep -qi "^ID=nixos" /etc/os-release 2>/dev/null; then
        local sudo_module="/etc/nixos/zapret-sudo.nix"
        local config_path="/etc/nixos/configuration.nix"

        read -p "Создать NixOS модуль sudo-правил и выполнить nixos-rebuild switch? (y/N): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "Отменено."
            read -p "Нажмите Enter для продолжения..."
            return 0
        fi

        elevate tee "$sudo_module" > /dev/null <<NIXEOF
{ config, pkgs, ... }:

{
  security.sudo.extraRules = [
    { users = [ "$user" ]; commands = [
      { command = "\${pkgs.nftables}/bin/nft *"; options = [ "NOPASSWD" ]; }
      { command = "\${pkgs.iptables}/bin/iptables *"; options = [ "NOPASSWD" ]; }
      { command = "\${pkgs.iptables}/bin/ip6tables *"; options = [ "NOPASSWD" ]; }
      { command = "$NFQWS_PATH *"; options = [ "NOPASSWD" ]; }
      { command = "\${pkgs.procps}/bin/pkill -f nfqws"; options = [ "NOPASSWD" ]; }
    ]; }
  ];
}
NIXEOF

        if ! grep -q "zapret-sudo.nix" "$config_path" 2>/dev/null; then
            local tmp
            tmp="$(mktemp)"
            elevate awk -v import="  ./zapret-sudo.nix" '
            /imports[[:space:]]*=[[:space:]]*\[/ {
                if ($0 ~ /];/) {
                    sub(/];/, sprintf("  %s\n  ];", import));
                    print
                } else {
                    print
                    in_imports = 1
                }
                next
            }
            in_imports && /];/ {
                printf "    %s\n%s\n", import, $0
                in_imports = 0
                next
            }
            { print }
            ' "$config_path" > "$tmp" 2>/dev/null

            if [[ -s "$tmp" ]] && ! diff -q "$config_path" "$tmp" >/dev/null 2>&1; then
                elevate cp "$tmp" "$config_path"
            fi
            rm -f "$tmp"
        fi

        local nix_path="${NIX_PATH:-nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixpkgs:nixos=/nix/var/nix/profiles/per-user/root/channels/nixos}"
        elevate env "NIX_PATH=$nix_path" nixos-rebuild switch || true
        echo "Готово."
        read -p "Нажмите Enter для продолжения..."
        return 0
    fi

    echo "Настройка sudoers для $user..."

    if [[ ! -d "/etc/sudoers.d" ]]; then
        show_error "Ошибка: /etc/sudoers.d не существует"
        return 0
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
    if [[ ! "${confirm:-Y}" =~ ^[Yy]$ ]]; then
        echo "Отменено"
        read -p "Нажмите Enter для продолжения..."
        return 0
    fi

    echo "$content" | elevate tee "$SUDOERS_FILE" > /dev/null || {
        show_error "Ошибка записи $SUDOERS_FILE"
        return 0
    }

    elevate chmod 440 "$SUDOERS_FILE"

    if command -v visudo >/dev/null 2>&1; then
        if ! elevate visudo -c -f "$SUDOERS_FILE" 2>/dev/null; then
            show_error "Ошибка синтаксиса! Удаляю файл..."
            elevate rm -f "$SUDOERS_FILE"
            return 0
        fi
    fi

    echo "Готово: $SUDOERS_FILE"
    read -p "Нажмите Enter для продолжения..."
    return 0
}

# -----------------------------------------------------------------------------
# Генерация doas.conf
# -----------------------------------------------------------------------------

generate_doas_rules() {
    local user="$1"
    local nfqws_path="${2:-$NFQWS_PATH}"
    local nft_path=$(get_cmd_path nft)

    local iptables_path=$(get_cmd_path iptables)
    local ip6tables_path=$(get_cmd_path ip6tables)

    cat <<EOF
# Zapret Discord YouTube - nopass для $user
permit nopass $user as root cmd $nft_path
permit nopass $user as root cmd $iptables_path
permit nopass $user as root cmd $ip6tables_path
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
        read -p "Нажмите Enter для продолжения..."
        return 0
    fi

    # Проверяем, есть ли уже наши правила
    if [[ -f "$DOAS_CONF" ]] && grep -q "# Zapret Discord YouTube" "$DOAS_CONF"; then
        echo "Правила уже есть в $DOAS_CONF"
        read -p "Заменить? [Y/n]: " replace
        if [[ "${replace:-Y}" =~ ^[Yy]$ ]]; then
            # Удаляем старый блок (от маркера до пустой строки или конца)
            elevate sed -i '/# Zapret Discord YouTube/,/^$/d' "$DOAS_CONF"
        else
            echo "Отменено"
            read -p "Нажмите Enter для продолжения..."
            return 0
        fi
    fi

    # Добавляем правила
    {
        echo ""
        echo "$rules"
    } | elevate tee -a "$DOAS_CONF" > /dev/null || {
        show_error "Ошибка записи в $DOAS_CONF"
        return 0
    }

    echo "Готово: правила добавлены в $DOAS_CONF"
    read -p "Нажмите Enter для продолжения..."
    return 0
}

# -----------------------------------------------------------------------------
# Главные функции
# -----------------------------------------------------------------------------

setup_permissions() {
    local user="${1:-$USER}"
    local system
    system=$(get_elevate_cmd) || {
        show_error "Ошибка: не найден sudo или doas"
        return 0
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
        "")
            # Для запуска от root
            setup_sudoers "$user"
            ;;
    esac
}

remove_permissions() {
    if [[ -f /etc/os-release ]] && grep -qi "^ID=nixos" /etc/os-release 2>/dev/null; then
        echo "На NixOS удалите правила sudo вручную из /etc/nixos/configuration.nix"
        echo "и выполните: sudo nixos-rebuild switch"
        return 0
    fi

    local removed=false

    if [[ -f "$SUDOERS_FILE" ]]; then
        elevate rm -f "$SUDOERS_FILE"
        echo "Удалён $SUDOERS_FILE"
        removed=true
    fi

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
