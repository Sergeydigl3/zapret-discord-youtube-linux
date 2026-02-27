#!/usr/bin/env bash

# SERVICE_NAME берётся из lib/constants.sh (подключается в service.sh)
SCAN_DIR="$(ps aux | grep 's6-svscan' | grep -oP 'X3 -- \K\S+')"
SERVICE_DIR="$SCAN_DIR/$SERVICE_NAME"
LOG_DIR="/var/log/$SERVICE_NAME"

# Функция для проверки статуса
check_service_status() {
    if [ ! -d "$SERVICE_DIR" ]; then
        echo "Статус: Сервис не установлен (директория отсутствует)."
        return 1
    fi

    if elevate s6-svstat "$SERVICE_DIR" 2>/dev/null | grep -q "up (pid"; then
        echo "Статус: Сервис активен (up)."
        return 2
    else
        echo "Статус: Сервис остановлен или ошибка (down)."
        return 3
    fi
}

# Функция установки
install_service() {
    local absolute_homedir_path="$(realpath "${HOME_DIR_PATH:-$HOME}")"
    local absolute_service_script_path="$absolute_homedir_path/service.sh"

    elevate mkdir -p "$SERVICE_DIR/log"
    elevate mkdir -p "$LOG_DIR"

    elevate bash -c "cat > $SERVICE_DIR/run" <<EOF
#!/bin/sh
exec 2>&1
cd "$absolute_homedir_path"
exec "$absolute_service_script_path" daemon
EOF

    elevate bash -c "cat > $SERVICE_DIR/finish" <<EOF
#!/bin/sh
"$absolute_service_script_path" kill
exit 0
EOF

    elevate bash -c "cat > $SERVICE_DIR/log/run" <<EOF
#!/bin/sh
exec s6-log n20 s1000000 "$LOG_DIR"
EOF

    elevate chmod +x "$SERVICE_DIR/run" "$SERVICE_DIR/finish" "$SERVICE_DIR/log/run"
    elevate s6-svscanctl -a "$SCAN_DIR"
    echo "Сервис установлен и должен запуститься автоматически."
}

# Функция для запуска сервиса
start_service() {
    echo "Запуск $SERVICE_NAME..."
    elevate rm "$SERVICE_DIR/down"
    elevate s6-svc -u "$SERVICE_DIR"
}

# Функция для остановки сервиса
stop_service() {
    echo "Остановка $SERVICE_NAME..."
    elevate touch "$SERVICE_DIR/down"
    elevate chmod +x "$SERVICE_DIR/down"
    sleep 1
    elevate s6-svc -d "$SERVICE_DIR"
    elevate s6-svc -d "$SERVICE_DIR/log"
}

# Функция для перезапуска сервиса
restart_service() {
    echo "Перезапуск $SERVICE_NAME..."
    elevate s6-svc -r "$SERVICE_DIR"
}

# Функция для удаления сервиса
remove_service() {
    echo "Удаление сервиса..."
    elevate touch "$SERVICE_DIR/down"
    elevate chmod +x "$SERVICE_DIR/down"
    sleep 1
    elevate s6-svc -d "$SERVICE_DIR" "$SERVICE_DIR/log"
    elevate rm -rf "$SERVICE_DIR"
    elevate s6-svscanctl -an "$SCAN_DIR"
    if pgrep -f "s6-supervise $SERVICE_NAME" >/dev/null; then
        elevate pkill -f "s6-supervise $SERVICE_NAME"
    fi
    echo "Сервис удален."
}
