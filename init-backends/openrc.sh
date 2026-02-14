#!/usr/bin/env bash

# SERVICE_NAME берётся из lib/constants.sh (подключается в service.sh)
SERVICE_FILE="/etc/init.d/$SERVICE_NAME"
LOG_FILE="/var/log/$SERVICE_NAME.log"

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

create_logrotate_conf() {
    sudo mkdir -p /etc/logrotate.d

    sudo bash -c "cat > /etc/logrotate.d/$SERVICE_NAME" <<EOF
/var/log/$SERVICE_NAME.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
    copytruncate
}
EOF

sudo chmod 0644 /etc/logrotate.d/$SERVICE_NAME
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
# /etc/init.d/$SERVICE_NAME

description="Zapret bypass для Discord/YouTube (nfqws + nftables)"

 : "\${HOMEDIR:=$absolute_homedir_path}"
 : "\${MAIN_SCRIPT:=\$HOMEDIR/main_script.sh}"
 : "\${STOP_SCRIPT:=\$HOMEDIR/stop_and_clean_nft.sh}"

command="/bin/bash"
command_args="\$MAIN_SCRIPT -nointeractive"
command_background="yes"
pidfile="/run/$SERVICE_NAME.pid"
directory="\$HOMEDIR"
kill_mode="mixed"
extra_commands="logs"

output_log="$LOG_FILE"
error_log="$LOG_FILE"

depend() {
    need net
    after firewall
}

start_pre() {
    if [ -z "\$LOG_FILE" ]; then
        eerror "LOG_FILE не задан!"
        return 1
    fi

    touch "\$LOG_FILE" 2>/dev/null || true

    if [ ! -f "\$LOG_FILE" ] || [ ! -w "\$LOG_FILE" ]; then
        ewarn "Не удалось создать/записать в лог-файл: \$LOG_FILE"
    fi

    return 0
}

post_stop() {
    if [[ -x "\$STOP_SCRIPT" ]]; then
        einfo "Выполняем очистку nftables..."
        "\$STOP_SCRIPT"
    fi
}

logs() {
    if [ ! -f "\$LOG_FILE" ]; then
        eerror "Файл лога \$LOG_FILE не найден."
        return 1
    fi

    tail -n 30 "\$LOG_FILE"
}
EOF
    create_logrotate_conf
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
