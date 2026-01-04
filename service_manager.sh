#!/usr/bin/env bash

# Модуль управления сервисами - поддержка systemd, openrc, sysvinit
# Сохраняет совместимость с существующим CLI интерфейсом

SERVICE_NAME="zapret_discord_youtube"
CONF_FILE="$(dirname "$0")/conf.env"
MAIN_SCRIPT_PATH="$(dirname "$0")/main_script.sh"
STOP_SCRIPT="$(dirname "$0")/stop_and_clean.sh"

# Импортируем общие функции
source "$(dirname "$0")/utils/common.sh"

# ==================== SYSTEMD FUNCTIONS ====================

# Функция для проверки статуса сервиса systemd
check_systemd_status() {
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

# Функция для установки systemd сервиса
install_systemd_service() {
    local absolute_homedir_path
    absolute_homedir_path="$(realpath "$(dirname "$0")")"
    local absolute_main_script_path
    absolute_main_script_path="$(realpath "$MAIN_SCRIPT_PATH")"
    local absolute_stop_script_path
    absolute_stop_script_path="$(realpath "$STOP_SCRIPT")"
    
    echo "Создание systemd сервиса для автозагрузки..."
    sudo bash -c "cat > /etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=Zapret Discord YouTube Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$absolute_homedir_path
User=root
ExecStart=/usr/bin/env bash $absolute_main_script_path -nointeractive
ExecStop=/usr/bin/env bash $absolute_stop_script_path
ExecStopPost=/usr/bin/env echo "Сервис завершён"
PIDFile=/run/$SERVICE_NAME.pid
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable "$SERVICE_NAME"
    sudo systemctl start "$SERVICE_NAME"
    echo "Сервис systemd успешно установлен и запущен."
}

# Функция для удаления systemd сервиса
remove_systemd_service() {
    echo "Удаление systemd сервиса..."
    sudo systemctl stop "$SERVICE_NAME"
    sudo systemctl disable "$SERVICE_NAME"
    sudo rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    sudo systemctl daemon-reload
    echo "Сервис systemd удален."
}

# Функция для запуска systemd сервиса
start_systemd_service() {
    echo "Запуск systemd сервиса..."
    sudo systemctl start "$SERVICE_NAME"
    echo "Сервис запущен."
    sleep 3
    check_nfqws_status
}

# Функция для остановки systemd сервиса
stop_systemd_service() {
    echo "Остановка systemd сервиса..."
    sudo systemctl stop "$SERVICE_NAME"
    echo "Сервис остановлен."
    # Вызов скрипта для остановки и очистки nftables
    "$STOP_SCRIPT"
}

# Функция для перезапуска systemd сервиса
restart_systemd_service() {
    stop_systemd_service
    sleep 1
    start_systemd_service
}

# ==================== OPENRC FUNCTIONS ====================

# Функция для проверки статуса сервиса OpenRC
check_openrc_status() {
    if ! rc-service "$SERVICE_NAME" status >/dev/null 2>&1; then
        echo "Статус: Сервис не установлен."
        return 1
    fi
    
    if rc-service "$SERVICE_NAME" status | grep -q "started"; then
        echo "Статус: Сервис установлен и активен."
        return 2
    else
        echo "Статус: Сервис установлен, но не активен."
        return 3
    fi
}

# Функция для установки OpenRC сервиса
install_openrc_service() {
    local absolute_homedir_path
    absolute_homedir_path="$(realpath "$(dirname "$0")")"
    local absolute_main_script_path
    absolute_main_script_path="$(realpath "$MAIN_SCRIPT_PATH")"
    local absolute_stop_script_path
    absolute_stop_script_path="$(realpath "$STOP_SCRIPT")"
    
    echo "Создание OpenRC сервиса для автозагрузки..."
    
    local service_file="/etc/init.d/$SERVICE_NAME"
    sudo bash -c "cat > $service_file" <<'EOF'
#!/sbin/openrc-run

description="Zapret Discord YouTube Service"
command="/usr/bin/env/bash"
command_args="ABSOLUTE_MAIN_SCRIPT_PATH -nointeractive"
command_background=false
pidfile="/run/${RC_SVCNAME}.pid"

depend() {
    need net
    after firewall
}

start_pre() {
    checkpath --directory --owner root:root --mode 0755 /run/${RC_SVCNAME}
}

stop() {
    ebegin "Stopping ${RC_SVCNAME}"
    /usr/bin/env/bash ABSOLUTE_STOP_SCRIPT_PATH
    eend $?
}
EOF
    
    # Заменяем плейсхолдеры
    sudo sed -i "s|ABSOLUTE_MAIN_SCRIPT_PATH|$absolute_main_script_path|g" "$service_file"
    sudo sed -i "s|ABSOLUTE_STOP_SCRIPT_PATH|$absolute_stop_script_path|g" "$service_file"
    
    sudo chmod +x "$service_file"
    sudo rc-update add "$SERVICE_NAME" default
    sudo rc-service "$SERVICE_NAME" start
    
    echo "Сервис OpenRC успешно установлен и запущен."
}

# Функция для удаления OpenRC сервиса
remove_openrc_service() {
    echo "Удаление OpenRC сервиса..."
    sudo rc-service "$SERVICE_NAME" stop
    sudo rc-update del "$SERVICE_NAME" default
    sudo rm -f "/etc/init.d/$SERVICE_NAME"
    echo "Сервис OpenRC удален."
}

# Функция для запуска OpenRC сервиса
start_openrc_service() {
    echo "Запуск OpenRC сервиса..."
    sudo rc-service "$SERVICE_NAME" start
    echo "Сервис запущен."
    sleep 3
    check_nfqws_status
}

# Функция для остановки OpenRC сервиса
stop_openrc_service() {
    echo "Остановка OpenRC сервиса..."
    sudo rc-service "$SERVICE_NAME" stop
    echo "Сервис остановлен."
    # Вызов скрипта для остановки и очистки nftables
    "$STOP_SCRIPT"
}

# Функция для перезапуска OpenRC сервиса
restart_openrc_service() {
    stop_openrc_service
    sleep 1
    start_openrc_service
}

# ==================== SYSVINIT FUNCTIONS ====================

# Функция для проверки статуса сервиса SysVinit
check_sysvinit_status() {
    if ! /etc/init.d/"$SERVICE_NAME" status >/dev/null 2>&1; then
        echo "Статус: Сервис не установлен."
        return 1
    fi
    
    if /etc/init.d/"$SERVICE_NAME" status | grep -q "running"; then
        echo "Статус: Сервис установлен и активен."
        return 2
    else
        echo "Статус: Сервис установлен, но не активен."
        return 3
    fi
}

# Функция для установки SysVinit сервиса
install_sysvinit_service() {
    local absolute_homedir_path
    absolute_homedir_path="$(realpath "$(dirname "$0")")"
    local absolute_main_script_path
    absolute_main_script_path="$(realpath "$MAIN_SCRIPT_PATH")"
    local absolute_stop_script_path
    absolute_stop_script_path="$(realpath "$STOP_SCRIPT")"
    
    echo "Создание SysVinit сервиса для автозагрузки..."
    
    local service_file="/etc/init.d/$SERVICE_NAME"
    sudo bash -c "cat > $service_file" <<'EOF'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          zapret_discord_youtube
# Required-Start:    $network $local_fs
# Required-Stop:     $network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Zapret Discord YouTube Service
### END INIT INFO

case "$1" in
    start)
        echo "Starting Zapret Discord YouTube"
        /usr/bin/env/bash ABSOLUTE_MAIN_SCRIPT_PATH -nointeractive
        ;;
    stop)
        echo "Stopping Zapret Discord YouTube"
        /usr/bin/env/bash ABSOLUTE_STOP_SCRIPT_PATH
        ;;
    restart)
        $0 stop
        sleep 1
        $0 start
        ;;
    status)
        if pgrep -f "nfqws" >/dev/null; then
            echo "Zapret Discord YouTube is running"
        else
            echo "Zapret Discord YouTube is not running"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
EOF
    
    # Заменяем плейсхолдеры
    sudo sed -i "s|ABSOLUTE_MAIN_SCRIPT_PATH|$absolute_main_script_path|g" "$service_file"
    sudo sed -i "s|ABSOLUTE_STOP_SCRIPT_PATH|$absolute_stop_script_path|g" "$service_file"
    
    sudo chmod +x "$service_file"
    
    # Добавляем в автозагрузку (разные дистрибутивы по-разному)
    if command -v update-rc.d >/dev/null 2>&1; then
        sudo update-rc.d "$SERVICE_NAME" defaults
    elif command -v chkconfig >/dev/null 2>&1; then
        sudo chkconfig --add "$SERVICE_NAME"
    fi
    
    sudo "$service_file" start
    
    echo "Сервис SysVinit успешно установлен и запущен."
}

# Функция для удаления SysVinit сервиса
remove_sysvinit_service() {
    echo "Удаление SysVinit сервиса..."
    sudo /etc/init.d/"$SERVICE_NAME" stop
    
    # Удаляем из автозагрузки
    if command -v update-rc.d >/dev/null 2>&1; then
        sudo update-rc.d -f "$SERVICE_NAME" remove
    elif command -v chkconfig >/dev/null 2>&1; then
        sudo chkconfig --del "$SERVICE_NAME"
    fi
    
    sudo rm -f "/etc/init.d/$SERVICE_NAME"
    echo "Сервис SysVinit удален."
}

# Функция для запуска SysVinit сервиса
start_sysvinit_service() {
    echo "Запуск SysVinit сервиса..."
    sudo /etc/init.d/"$SERVICE_NAME" start
    echo "Сервис запущен."
    sleep 3
    check_nfqws_status
}

# Функция для остановки SysVinit сервиса
stop_sysvinit_service() {
    echo "Остановка SysVinit сервиса..."
    sudo /etc/init.d/"$SERVICE_NAME" stop
    echo "Сервис остановлен."
    # Вызов скрипта для остановки и очистки nftables
    "$STOP_SCRIPT"
}

# Функция для перезапуска SysVinit сервиса
restart_sysvinit_service() {
    stop_sysvinit_service
    sleep 1
    start_sysvinit_service
}

# ==================== WRAPPER FUNCTIONS ====================

# Основное меню управления (совместимое с существующим CLI)
show_menu() {
    local init_system=$(detect_init_system)
    
    case "$init_system" in
        "systemd")
            check_systemd_status
            local status=$?
            ;;
        "openrc")
            check_openrc_status
            local status=$?
            ;;
        "sysvinit")
            check_sysvinit_status
            local status=$?
            ;;
        *)
            echo "Ошибка: Неизвестная система инициализации"
            return 1
            ;;
    esac

    case $status in
    1)
        echo "1. Установить и запустить сервис"
        echo "2. Изменить конфигурацию"
        read -p "Выберите действие: " choice
        case $choice in
        1) install_service ;;
        2) edit_conf_file ;;
        esac
        ;;
    2)
        echo "1. Удалить сервис"
        echo "2. Остановить сервис"
        echo "3. Перезапустить сервис"
        echo "4. Изменить конфигурацию"
        read -p "Выберите действие: " choice
        case $choice in
        1) remove_service ;;
        2) stop_service ;;
        3) restart_service ;;
        4) edit_conf_file ;;
        esac
        ;;
    3)
        echo "1. Удалить сервис"
        echo "2. Запустить сервис"
        echo "3. Изменить конфигурацию"
        read -p "Выберите действие: " choice
        case $choice in
        1) remove_service ;;
        2) start_service ;;
        3) edit_conf_file ;;
        esac
        ;;
    *)
        echo "Неправильный выбор."
        ;;
    esac
}

# Общие функции для всех систем

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
    
    local init_system=$(detect_init_system)
    
    case "$init_system" in
        "systemd")
            install_systemd_service
            ;;
        "openrc")
            install_openrc_service
            ;;
        "sysvinit")
            install_sysvinit_service
            ;;
        *)
            echo "Ошибка: Неизвестная система инициализации"
            ;;
    esac
}

remove_service() {
    local init_system=$(detect_init_system)
    
    case "$init_system" in
        "systemd")
            remove_systemd_service
            ;;
        "openrc")
            remove_openrc_service
            ;;
        "sysvinit")
            remove_sysvinit_service
            ;;
        *)
            echo "Ошибка: Неизвестная система инициализации"
            ;;
    esac
}

start_service() {
    local init_system=$(detect_init_system)
    
    case "$init_system" in
        "systemd")
            start_systemd_service
            ;;
        "openrc")
            start_openrc_service
            ;;
        "sysvinit")
            start_sysvinit_service
            ;;
        *)
            echo "Ошибка: Неизвестная система инициализации"
            ;;
    esac
}

stop_service() {
    local init_system=$(detect_init_system)
    
    case "$init_system" in
        "systemd")
            stop_systemd_service
            ;;
        "openrc")
            stop_openrc_service
            ;;
        "sysvinit")
            stop_sysvinit_service
            ;;
        *)
            echo "Ошибка: Неизвестная система инициализации"
            ;;
    esac
}

restart_service() {
    local init_system=$(detect_init_system)
    
    case "$init_system" in
        "systemd")
            restart_systemd_service
            ;;
        "openrc")
            restart_openrc_service
            ;;
        "sysvinit")
            restart_sysvinit_service
            ;;
        *)
            echo "Ошибка: Неизвестная система инициализации"
            ;;
    esac
}

edit_conf_file() {
    echo "Изменение конфигурации..."
    create_conf_file
    echo "Конфигурация обновлена."

    local init_system=$(detect_init_system)
    
    # Если сервис активен, предлагаем перезапустить
    case "$init_system" in
        "systemd")
            if systemctl is-active --quiet "$SERVICE_NAME"; then
                read -p "Сервис активен. Перезапустить сервис для применения новых настроек? (Y/n): " answer
                if [[ ${answer:-Y} =~ ^[Yy]$ ]]; then
                    restart_service
                fi
            fi
            ;;
        "openrc")
            if rc-service "$SERVICE_NAME" status | grep -q "started"; then
                read -p "Сервис активен. Перезапустить сервис для применения новых настроек? (Y/n): " answer
                if [[ ${answer:-Y} =~ ^[Yy]$ ]]; then
                    restart_service
                fi
            fi
            ;;
        "sysvinit")
            if /etc/init.d/"$SERVICE_NAME" status | grep -q "running"; then
                read -p "Сервис активен. Перезапустить сервис для применения новых настроек? (Y/n): " answer
                if [[ ${answer:-Y} =~ ^[Yy]$ ]]; then
                    restart_service
                fi
            fi
            ;;
    esac
}

# Запуск меню
show_menu

# Пауза перед выходом
echo ""
read -p "Нажмите Enter для выхода..."