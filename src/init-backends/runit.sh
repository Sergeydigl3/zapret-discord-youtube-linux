#!/usr/bin/env bash

# SERVICE_NAME берётся из lib/constants.sh (подключается в service.sh)
SERVICE_DIR="/etc/sv/$SERVICE_NAME"
SCAN_DIR="$(ps aux | grep 'runsvdir' | grep -oP '\-P \K\S+')"

# Функция проверки статуса сервиса
check_service_status() {
    if [[ ! -d "$SERVICE_DIR" ]]; then
        echo "Статус: Сервис не установлен."
        return 1
    fi

    local status=$(elevate sv status "$SERVICE_NAME" | awk '{print $1}')
    if [[ "$status" == "run:" ]]; then
        echo "Статус: Сервис активен."
        return 2
    else
        echo "Статус: Сервис установлен, но не активен."
        return 3
    fi
}

# Функция установки сервиса
install_service() {
    # Получение абсолютного пути
    local absolute_homedir_path
    absolute_homedir_path="$(realpath "$HOME_DIR_PATH")"
    local absolute_service_script_path
    absolute_service_script_path="$absolute_homedir_path/service.sh"

    elevate mkdir -p "$SERVICE_DIR"
    elevate tee "$SERVICE_DIR/run" >/dev/null <<EOF
#!/bin/sh
exec 2>&1
exec "$absolute_service_script_path" daemon
EOF

    elevate tee "$SERVICE_DIR/finish" >/dev/null <<EOF
#!/bin/sh
exec 2>&1
exec "$absolute_service_script_path" kill
EOF

    # Установка прав
    elevate chmod 755 "$SERVICE_DIR/run" "$SERVICE_DIR/finish"
    elevate chown -R root:root "$SERVICE_DIR"

    # Активация сервиса
    if [[ ! -L "$SERVICE_DIR" ]]; then
        elevate ln -sf "$SERVICE_DIR" "$SCAN_DIR/$SERVICE_NAME"
        echo "Сервис добавлен в автозагрузку."
    fi

    elevate sv up "$SERVICE_NAME"
    sleep 2

    if elevate sv status "$SERVICE_NAME" | grep -q "^run:"; then
        echo "Сервис успешно установлен и запущен."
    else
        return 1
    fi
}

# Функция запуска сервиса
start_service() {
    echo "Запуск сервиса..."
    elevate sv up "$SERVICE_NAME"
    sleep 1
    check_service_status
}

# Функция остановки сервиса
stop_service() {
    echo "Остановка сервиса..."
    elevate sv down "$SERVICE_NAME"
    sleep 1
    check_service_status
}

# Функция перезапуска сервиса
restart_service() {
    elevate sv down "$SERVICE_NAME"
    sleep 5
    echo "Перезапуск сервиса..."
    elevate sv up "$SERVICE_NAME"

    check_service_status
}

# Функция удаления сервиса
remove_service() {
    echo "Остановка и удаление сервиса..."

    if [[ -d "$SERVICE_DIR" ]]; then
        elevate sv down "$SERVICE_NAME" 2>/dev/null || true
        sleep 2
    fi

    elevate rm -rf "$SERVICE_DIR"
    elevate rm "$SCAN_DIR/$SERVICE_NAME"

    if pgrep -f "runsv $SERVICE_NAME" >/dev/null; then
        elevate pkill -f "runsv $SERVICE_NAME"
    fi

    echo "Сервис полностью удалён."
}
