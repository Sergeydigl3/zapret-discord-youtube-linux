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
    # Проверяем и создаём конфиг если нужно
    ensure_config_exists || return 1

    local desktop_file="/usr/share/applications/zapret-discord-youtube.desktop"
    local script_path="$BASE_DIR/service.sh"

    log "Создание системного ярлыка..."

    # Создаём desktop файл
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

    # Обновляем базу desktop файлов если есть update-desktop-database
    if command -v update-desktop-database >/dev/null 2>&1; then
        elevate update-desktop-database /usr/share/applications 2>/dev/null || true
    fi

    echo "Системный ярлык создан: $desktop_file"
    echo "Ярлык доступен всем пользователям в меню системы"
    echo ""
    echo "Для работы без пароля: ./service.sh setup-permissions"
}

# Функция удаления desktop ярлыка
remove_desktop_shortcut() {
    local desktop_file="/usr/share/applications/zapret-discord-youtube.desktop"

    if [[ -f "$desktop_file" ]]; then
        log "Удаление системного ярлыка..."
        elevate rm -f "$desktop_file" || handle_error "Не удалось удалить ярлык"

        # Обновляем базу desktop файлов если есть update-desktop-database
        if command -v update-desktop-database >/dev/null 2>&1; then
            elevate update-desktop-database /usr/share/applications 2>/dev/null || true
        fi

        echo "✓ Системный ярлык удалён: $desktop_file"
    else
        echo "Ярлык не найден: $desktop_file"
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
