#!/usr/bin/env bash

# =============================================================================
# Управление desktop ярлыком для zapret-discord-youtube-linux
# =============================================================================

# Guard: проверяем что файл не был уже загружен
[[ -n "${_DESKTOP_SH_LOADED:-}" ]] && return 0
_DESKTOP_SH_LOADED=1

# Подключаем константы и общие функции
source "$(dirname "${BASH_SOURCE[0]}")/constants.sh"
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# -----------------------------------------------------------------------------
# Функции управления desktop ярлыком
# -----------------------------------------------------------------------------

# Функция создания desktop ярлыка
create_desktop_shortcut() {
    ensure_config_exists || return 1

    local script_path="$BASE_DIR/service.sh"
    local is_nixos=false
    [[ -f /etc/os-release ]] && grep -qi "^ID=nixos" /etc/os-release 2>/dev/null && is_nixos=true

    if $is_nixos; then
        local desktop_file="$HOME/.local/share/applications/zapret-discord-youtube.desktop"
        log "Создание ярлыка для текущего пользователя..."

        mkdir -p "$(dirname "$desktop_file")"
        tee "$desktop_file" > /dev/null <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Zapret Discord YouTube
Comment=Обход замедления YouTube и Discord
Exec=bash -c 'cd "${BASE_DIR}" && bash "${script_path}" daemon'
Icon=network-workgroup
Terminal=true
Categories=Network;System;
Keywords=zapret;youtube;discord;dpi;
EOF
        chmod +x "$desktop_file"

        echo "Ярлык создан: $desktop_file"
    else
        local desktop_file="/usr/share/applications/zapret-discord-youtube.desktop"

        log "Создание системного ярлыка..."
        elevate tee "$desktop_file" > /dev/null <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Zapret Discord YouTube
Comment=Обход замедления YouTube и Discord
Exec=bash -c 'cd "${BASE_DIR}" && bash "${script_path}" daemon'
Icon=network-workgroup
Terminal=true
Categories=Network;System;
Keywords=zapret;youtube;discord;dpi;
EOF

        elevate chmod +x "$desktop_file" || handle_error "Не удалось установить права на ярлык"

        if command -v update-desktop-database >/dev/null 2>&1; then
            elevate update-desktop-database /usr/share/applications 2>/dev/null || true
        fi

        echo "Системный ярлык создан: $desktop_file"
        echo "Ярлык доступен всем пользователям в меню системы"
    fi

    echo ""
    echo "Для работы без пароля: ./service.sh setup-permissions"
}

# Функция удаления desktop ярлыка
remove_desktop_shortcut() {
    local is_nixos=false
    [[ -f /etc/os-release ]] && grep -qi "^ID=nixos" /etc/os-release 2>/dev/null && is_nixos=true

    local desktop_file
    if $is_nixos; then
        desktop_file="$HOME/.local/share/applications/zapret-discord-youtube.desktop"
    else
        desktop_file="/usr/share/applications/zapret-discord-youtube.desktop"
    fi

    if [[ -f "$desktop_file" ]]; then
        log "Удаление ярлыка..."

        if $is_nixos; then
            rm -f "$desktop_file" || handle_error "Не удалось удалить ярлык"
        else
            elevate rm -f "$desktop_file" || handle_error "Не удалось удалить ярлык"
            if command -v update-desktop-database >/dev/null 2>&1; then
                elevate update-desktop-database /usr/share/applications 2>/dev/null || true
            fi
        fi

        echo "✓ Ярлык удалён: $desktop_file"
    else
        echo -e "\e[31mОшибка: Ярлык не найден: $desktop_file\e[0m"
        return 0
    fi
}

# Показать справку по desktop
show_desktop_usage() {
    cat <<EOF
Управление desktop ярлыком

Использование:
  $(basename "$0") desktop install    - Создать ярлык в меню приложений
  $(basename "$0") desktop remove     - Удалить ярлык из меню приложений
  $(basename "$0") desktop --help     - Показать эту справку

Примеры:
  # Создать ярлык
  bash service.sh desktop install

  # Удалить ярлык
  bash service.sh desktop remove

После установки системный ярлык появится в меню приложений всех пользователей
в категории "Сеть" или "Система".
При запуске откроется терминал и zapret запустится с настройками из conf.env.
EOF
}
