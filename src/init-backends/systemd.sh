#!/usr/bin/env bash

# SERVICE_NAME берётся из lib/constants.sh (подключается в service.sh)
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"

# Функция для проверки статуса сервиса
check_service_status() {
    if ! systemctl list-unit-files | grep -q "$SERVICE_NAME.service"; then
        echo "Статус: Сервис не установлен."
        return 1
    fi

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "Статус: Сервис установлен и активен."
        return 2
    else
        echo "Статус: Сервис установлен, но не активен."
        return 3
    fi
}

# Функция для установки сервиса
install_service() {
    # Получение абсолютного пути
    local absolute_homedir_path
    absolute_homedir_path="$(realpath "$HOME_DIR_PATH")"
    local absolute_service_script_path
    absolute_service_script_path="$absolute_homedir_path/service.sh"

    echo "Создание systemd сервиса для автозагрузки..."
    elevate bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=Custom Script Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$absolute_homedir_path
User=root
ExecStart=/usr/bin/env bash $absolute_service_script_path daemon
ExecStop=/usr/bin/env bash $absolute_service_script_path kill
ExecStopPost=/usr/bin/env echo "Сервис завершён"
PIDFile=/run/$SERVICE_NAME.pid

[Install]
WantedBy=multi-user.target
EOF
    elevate systemctl daemon-reload
    elevate systemctl enable "$SERVICE_NAME"
    elevate systemctl start "$SERVICE_NAME"
    echo "Сервис успешно установлен и запущен."
}

# Функция для удаления сервиса
remove_service() {
    echo "Удаление сервиса..."
    elevate systemctl stop "$SERVICE_NAME"
    elevate systemctl disable "$SERVICE_NAME"
    elevate rm -f "$SERVICE_FILE"
    elevate systemctl daemon-reload
    echo "Сервис удален."
}

# Функция для запуска сервиса
start_service() {
    echo "Запуск сервиса..."
    elevate systemctl start "$SERVICE_NAME"
    echo "Сервис запущен."
    sleep 3
    check_nfqws_status
}

# Функция для остановки сервиса
stop_service() {
    echo "Остановка сервиса..."
    elevate systemctl stop "$SERVICE_NAME"
    echo "Сервис остановлен."
}

# Функция для перезапуска сервиса
restart_service() {
    stop_service
    sleep 1
    start_service
}
