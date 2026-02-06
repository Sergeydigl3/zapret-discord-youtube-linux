#!/usr/bin/env bash

# Константы
SERVICE_NAME="zapret_discord_youtube"
SERVICE_DIR="/etc/sv/$SERVICE_NAME"
SCAN_DIR="$(ps aux | grep 'runsvdir' | grep -oP '\-P \K\S+')"

# Функция проверки статуса сервиса
check_service_status() {
    if [[ ! -d "$SERVICE_DIR" ]]; then
        echo "Статус: Сервис не установлен."
        return 1
    fi

    local status=$(sudo sv status "$SERVICE_NAME" | awk '{print $1}')
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
    # Если конфиг отсутствует или неполный — создаём его интерактивно
    if ! check_conf_file; then
        read -p "Конфигурация отсутствует или неполная. Создать конфигурацию сейчас? (y/n): " answer
        if [[ $answer =~ ^[Yy]$ ]]; then
            create_conf_file
        else
            echo "Установка отменена."
            return 1
        fi
        if ! check_conf_file; then
            echo "Файл конфигурации всё ещё некорректен. Установка отменена."
            return 1
        fi
    fi

    # Получение абсолютного пути к основному скрипту и скрипту остановки
    local absolute_homedir_path
    absolute_homedir_path="$(realpath "$HOME_DIR_PATH")"
    local absolute_main_script_path
    absolute_main_script_path="$(realpath "$MAIN_SCRIPT_PATH")"
    local absolute_stop_script_path
    absolute_stop_script_path="$(realpath "$STOP_SCRIPT")"

    sudo mkdir -p "$SERVICE_DIR"
    sudo tee "$SERVICE_DIR/run" >/dev/null <<EOF
#!/bin/sh
exec 2>&1
exec "$absolute_main_script_path" -nointeractive
EOF

    sudo tee "$SERVICE_DIR/finish" >/dev/null <<EOF
#!/bin/sh
exec 2>&1
exec "$absolute_stop_script_path"
EOF

    # Установка прав
    sudo chmod 755 "$SERVICE_DIR/run" "$SERVICE_DIR/finish"
    sudo chown -R root:root "$SERVICE_DIR"

    # Активация сервиса
    if [[ ! -L "$SERVICE_DIR" ]]; then
        sudo ln -sf "$SERVICE_DIR" "$SCAN_DIR/$SERVICE_NAME"
        echo "Сервис добавлен в автозагрузку."
    fi

    sudo sv up "$SERVICE_NAME"
    sleep 2

    if sudo sv status "$SERVICE_NAME" | grep -q "^run:"; then
        echo "Сервис успешно установлен и запущен."
    else
        return 1
    fi
}

# Функция запуска сервиса
start_service() {
    echo "Запуск сервиса..."
    sudo sv up "$SERVICE_NAME"
    sleep 1
    check_service_status
}

# Функция остановки сервиса
stop_service() {
    echo "Остановка сервиса..."
    sudo sv down "$SERVICE_NAME"
    sleep 1
    check_service_status
}

# Функция перезапуска сервиса
restart_service() {
    sudo sv down "$SERVICE_NAME"
    sleep 5
    echo "Перезапуск сервиса..."
    sudo sv up "$SERVICE_NAME"

    check_service_status
}

# Функция удаления сервиса
remove_service() {
    echo "Остановка и удаление сервиса..."

    if [[ -d "$SERVICE_DIR" ]]; then
        sudo sv down "$SERVICE_NAME" 2>/dev/null || true
        sleep 2
    fi

    sudo rm -rf "$SERVICE_DIR"
    sudo rm "$SCAN_DIR/$SERVICE_NAME"

    if pgrep -f "runsv $SERVICE_NAME" >/dev/null; then
        sudo pkill -f "runsv $SERVICE_NAME"
    fi

    echo "Сервис полностью удалён."
}
