#!/usr/bin/env bash

# Константы
SERVICE_NAME="zapret_discord_youtube"
SERVICE_FILE="/etc/dinit.d/$SERVICE_NAME"

# Функция для проверки статуса сервиса
check_service_status() {
    if ! sudo dinitctl list | grep -q "$SERVICE_NAME"; then
        echo "Статус: Сервис не установлен."
        return 1
    fi

    if sudo dinitctl is-started "$SERVICE_NAME"; then
        echo "Статус: Сервис установлен и активен."
        return 2
    else
        echo "Статус: Сервис установлен, но не активен."
        return 3
    fi
}

# Функция для установки сервиса
install_service() {
    # Если конфиг отсутствует или неполный — создаём его интерактивно
    if ! check_conf_file; then
        read -p "Конфигурация отсутствует или неполная. Создать конфигурацию сейчас? (y/n): " answer
        if [[ $answer =~ ^[Yy]$ ]]; then
            create_conf_file
        else
            echo "Установка отменена."
            return
        fi
        # Перепроверяем конфигурацию
        if ! check_conf_file; then
            echo "Файл конфигурации все еще некорректен. Установка отменена."
            return
        fi
    fi

    # Получение абсолютного пути к основному скрипту и скрипту остановки
    local absolute_homedir_path
    absolute_homedir_path="$(realpath "$HOME_DIR_PATH")"
    local absolute_main_script_path
    absolute_main_script_path="$(realpath "$MAIN_SCRIPT_PATH")"
    local absolute_stop_script_path
    absolute_stop_script_path="$(realpath "$STOP_SCRIPT")"

    echo "Создание сервиса для автозагрузки..."
    sudo bash -c "cat > $SERVICE_FILE" <<EOF
type = process
command = /usr/bin/env bash "$absolute_main_script_path" -nointeractive
stop-command = /usr/bin/env bash "$absolute_stop_script_path"
# depends-on = network

restart = on-failure
restart-delay = 0.5
restart-limit-count = 4
EOF
    sudo dinitctl enable "$SERVICE_NAME"
    echo "Сервис успешно установлен и запущен."
}

# Функция для удаления сервиса
remove_service() {
    echo "Удаление сервиса..."
    sudo dinitctl stop "$SERVICE_NAME"
    sudo dinitctl disable "$SERVICE_NAME"
    sudo dinitctl unload "$SERVICE_NAME"
    sleep 1
    sudo rm -f "$SERVICE_FILE"
    echo "Сервис удален."
}

# Функция для запуска сервиса
start_service() {
    echo "Запуск сервиса..."
    sudo dinitctl start "$SERVICE_NAME"
    echo "Сервис запущен."
    sleep 3
    check_nfqws_status
}

# Функция для остановки сервиса
stop_service() {
    echo "Остановка сервиса..."
    sudo dinitctl stop "$SERVICE_NAME"
    echo "Сервис остановлен."
    # Вызов скрипта для остановки и очистки nftables
    $STOP_SCRIPT
}

# Функция для перезапуска сервиса
restart_service() {
    stop_service
    sleep 1
    start_service
}
