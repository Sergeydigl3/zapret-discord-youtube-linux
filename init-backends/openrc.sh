#!/usr/bin/env bash

# Константы
SERVICE_NAME="zapret_discord_youtube"
SERVICE_FILE="/etc/init.d/$SERVICE_NAME"

# Функция для проверки статуса сервиса
check_service_status() {
    if [[ ! -f "/etc/init.d/$SERVICE_NAME" ]]; then
        echo "Статус: Сервис не установлен."
        return 1
    fi

    if rc-service "$SERVICE_NAME" status >/dev/null 2>&1; then
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
    
    echo "Создание openrc сервиса для автозагрузки..."
    sudo bash -c "cat > $SERVICE_FILE" <<EOF
#!/sbin/openrc-run
# /etc/init.d/zapret_discord_youtube

description="Zapret bypass для Discord/YouTube (nfqws + nftables)"

 : "${HOMEDIR:=$absolute_homedir_path}"
 : "${MAIN_SCRIPT:=$HOMEDIR/main_script.sh}"
 : "${STOP_SCRIPT:=$HOMEDIR/stop_and_clean_nft.sh}"

command="/bin/bash"
command_args="$MAIN_SCRIPT -nointeractive"
command_background="yes"
pidfile="/run/zapret_discord_youtube.pid"
directory="$HOMEDIR"
# command_user="root:root"
kill_mode="mixed" 

depend() {
    need net
    after firewall
    # use net.eth0
}

post_stop() {
    if [[ -x "$STOP_SCRIPT" ]]; then
        einfo "Выполняем очистку nftables..."
        "$STOP_SCRIPT"
    fi
}
EOF
    sudo chmod +x "$SERVICE_FILE"
    sudo rc-update add "$SERVICE_NAME" default
    sudo rc-service "$SERVICE_NAME" restart
    echo "Сервис успешно установлен и запущен."
}

# Функция для удаления сервиса
remove_service() {
    echo "Удаление сервиса..."
    sudo rc-service "$SERVICE_NAME" stop
    $STOP_SCRIPT
    sudo rc-update del "$SERVICE_NAME" default
    sudo rm -f "$SERVICE_FILE"
    echo "Сервис удален."
}

# Функция для запуска сервиса
start_service() {
    echo "Запуск сервиса..."
    sudo rc-service "$SERVICE_NAME" restart
    echo "Сервис запущен."
    sleep 3
    check_nfqws_status
}

# Функция для остановки сервиса
stop_service() {
    echo "Остановка сервиса..."
    sudo rc-service "$SERVICE_NAME" stop
    echo "Сервис остановлен."
    $STOP_SCRIPT
}

# Функция для перезапуска сервиса
restart_service() {
    stop_service
    sleep 1
    start_service
}
