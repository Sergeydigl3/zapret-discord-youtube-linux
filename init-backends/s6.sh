#!/usr/bin/env bash

# Константы
SERVICE_NAME="zapret_discord_youtube"
SCAN_DIR="/run/service/"
SERVICE_DIR="$SCAN_DIR/$SERVICE_NAME"
LOG_DIR="/var/log/$SERVICE_NAME"

# Функция для проверки статуса
check_service_status() {
    if [ ! -d "$SERVICE_DIR" ]; then
        echo "Статус: Сервис не установлен (директория отсутствует)."
        return 1
    fi

    if sudo s6-svstat "$SERVICE_DIR" 2>/dev/null | grep -q "up (pid"; then
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
    local absolute_main_script_path="$(realpath "${MAIN_SCRIPT_PATH:-$HOME/main_script.sh}")"
    local absolute_stop_script_path="$(realpath "${STOP_SCRIPT:-$HOME/stop_and_clean_nft.sh}")"

    sudo mkdir -p "$SERVICE_DIR/log"
    sudo mkdir -p "$LOG_DIR"

    sudo bash -c "cat > $SERVICE_DIR/run" <<EOF
#!/bin/sh
exec 2>&1
cd "$absolute_homedir_path"
exec "$absolute_main_script_path" -nointeractive
EOF

    sudo bash -c "cat > $SERVICE_DIR/finish" <<EOF
#!/bin/sh
"$absolute_stop_script_path"
exit 0
EOF

    sudo bash -c "cat > $SERVICE_DIR/log/run" <<EOF
#!/bin/sh
exec s6-log n20 s1000000 "$LOG_DIR"
EOF

    sudo chmod +x "$SERVICE_DIR/run" "$SERVICE_DIR/finish" "$SERVICE_DIR/log/run"

    echo "Оповещение s6-svscan о новой директории..."
    sudo s6-svscanctl -a "$SCAN_DIR"

    echo "Сервис установлен и должен запуститься автоматически."
}

# Функция для запуска сервиса
start_service() {
    echo "Запуск $SERVICE_NAME..."
    sudo rm "$SERVICE_DIR/down"
    sudo s6-svc -u "$SERVICE_DIR"
}

# Функция для остановки сервиса
stop_service() {
    echo "Остановка $SERVICE_NAME..."
    sudo touch "$SERVICE_DIR/down"
    sudo chmod +x "$SERVICE_DIR/down"
    sleep 1
    sudo s6-svc -d "$SERVICE_DIR"
    sudo s6-svc -d "$SERVICE_DIR/log"
}

# Функция для перезапуска сервиса
restart_service() {
    echo "Перезапуск $SERVICE_NAME..."
    sudo s6-svc -r "$SERVICE_DIR"
}

# Функция для удаления сервиса
remove_service() {
    echo "Удаление сервиса..."
    sudo touch "$SERVICE_DIR/down"
    sudo chmod +x "$SERVICE_DIR/down"
    sleep 1
    sudo s6-svc -d "$SERVICE_DIR" "$SERVICE_DIR/log"
    sudo rm -rf "$SERVICE_DIR"
    sudo s6-svscanctl -an "$SCAN_DIR"
    if pgrep -f "s6-supervise $SERVICE_NAME" >/dev/null; then
        sudo pkill -f "s6-supervise $SERVICE_NAME"
    fi
    echo "Сервис удален."
}
