#!/usr/bin/env bash

# SERVICE_NAME берётся из lib/constants.sh (подключается в service.sh)
SERVICE_FILE="/etc/init.d/$SERVICE_NAME"
LOG_FILE="/var/log/$SERVICE_NAME.log"

# Функция для проверки статуса сервиса
check_service_status() {
    if [[ ! -f "$SERVICE_FILE" ]]; then
        echo "Статус: Сервис не установлен."
        return 1
    fi

    # Статус отдаёт сам init-скрипт: pid-файл читается только под root,
    # поэтому вызов идёт через elevate
    if elevate "$SERVICE_FILE" status >/dev/null 2>&1; then
        echo "Статус: Сервис установлен и активен."
        return 2
    else
        echo "Статус: Сервис установлен, но не активен."
        return 3
    fi
}

# Текст init-скрипта для /etc/init.d/$SERVICE_NAME
# Аргумент: $1 - абсолютный путь к каталогу, где лежит service.sh
render_sysvinit_script() {
    local homedir="$1"
    local template
    template=$(cat <<'INIT_SCRIPT'
#!/bin/sh
# chkconfig: 2345 20 80
# description: Zapret bypass для Discord/YouTube (nfqws + файрвол)
### BEGIN INIT INFO
# Provides:          @SERVICE_NAME@
# Required-Start:    $network $remote_fs
# Required-Stop:     $network $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Zapret bypass для Discord/YouTube (nfqws + файрвол)
# Description:       Поднимает nfqws и правила файрвола по выбранной стратегии.
### END INIT INFO

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

NAME="@SERVICE_NAME@"
HOMEDIR="@HOMEDIR@"
SERVICE_SCRIPT="$HOMEDIR/service.sh"
LOG_FILE="/var/log/$NAME.log"

if [ -d /run ]; then
    PIDFILE="/run/$NAME.pid"
else
    PIDFILE="/var/run/$NAME.pid"
fi

# PID демона, если он жив
running_pid() {
    [ -r "$PIDFILE" ] || return 1

    _pid=$(cat "$PIDFILE" 2>/dev/null)
    [ -n "$_pid" ] || return 1

    if [ -r "/proc/$_pid/stat" ]; then
        # Первое поле после имени - состояние; Z значит процесс уже завершился
        _state=$(sed 's/^.*) //; s/ .*//' "/proc/$_pid/stat" 2>/dev/null)
        [ -n "$_state" ] || return 1
        [ "$_state" = "Z" ] && return 1
    else
        kill -0 "$_pid" 2>/dev/null || return 1
    fi

    echo "$_pid"
}

do_start() {
    if _running=$(running_pid); then
        echo "$NAME уже запущен (pid $_running)."
        return 0
    fi

    rm -f "$PIDFILE"

    if [ ! -x "$SERVICE_SCRIPT" ]; then
        echo "Ошибка: $SERVICE_SCRIPT не найден или не исполняем." >&2
        return 1
    fi

    if [ ! -f "$HOMEDIR/conf.env" ]; then
        echo "Ошибка: $HOMEDIR/conf.env не найден. Настройте конфигурацию через service.sh." >&2
        return 1
    fi

    touch "$LOG_FILE" 2>/dev/null

    cd "$HOMEDIR" || return 1
    # nohup защищает демон от SIGHUP при закрытии терминала,
    # из которого запускали service.sh
    nohup /bin/bash "$SERVICE_SCRIPT" daemon >>"$LOG_FILE" 2>&1 </dev/null &
    echo "$!" > "$PIDFILE"

    sleep 2
    if ! running_pid >/dev/null; then
        rm -f "$PIDFILE"
        echo "Ошибка: $NAME завершился сразу после запуска, см. $LOG_FILE" >&2
        return 1
    fi

    echo "$NAME запущен (pid $(cat "$PIDFILE"))."
    return 0
}

do_stop() {
    if _pid=$(running_pid); then
        # Дети демона: run_zapret_command держит в фоне sleep infinity,
        # он переживает SIGTERM и остаётся сиротой, поэтому запоминаем их заранее
        _children=""
        if command -v pgrep >/dev/null 2>&1; then
            _children=$(pgrep -P "$_pid" 2>/dev/null)
        fi

        # SIGTERM: демон по trap сам останавливает nfqws и чистит файрвол
        kill -TERM "$_pid" 2>/dev/null
        _i=0
        while [ "$_i" -lt 10 ] && running_pid >/dev/null; do
            sleep 1
            _i=$((_i + 1))
        done
        running_pid >/dev/null && kill -KILL "$_pid" 2>/dev/null

        for _child in $_children; do
            kill -TERM "$_child" 2>/dev/null
        done
        echo "$NAME остановлен."
    else
        echo "$NAME не запущен."
    fi

    rm -f "$PIDFILE"

    # Страховка: демон мог не дойти до trap (например, убит через KILL)
    /bin/bash "$SERVICE_SCRIPT" kill >/dev/null 2>&1 || true
    return 0
}

do_status() {
    if _pid=$(running_pid); then
        echo "$NAME запущен (pid $_pid)."
        return 0
    fi

    echo "$NAME не запущен."
    return 3
}

case "$1" in
    start)
        do_start
        ;;
    stop)
        do_stop
        ;;
    restart|force-reload)
        do_stop
        do_start
        ;;
    status)
        do_status
        ;;
    *)
        echo "Использование: $0 {start|stop|restart|force-reload|status}" >&2
        exit 2
        ;;
esac

exit $?
INIT_SCRIPT
)

    template="${template//@SERVICE_NAME@/$SERVICE_NAME}"
    printf '%s\n' "${template//@HOMEDIR@/$homedir}"
}

create_logrotate_conf() {
    elevate mkdir -p /etc/logrotate.d

    elevate bash -c "cat > /etc/logrotate.d/$SERVICE_NAME" <<EOF
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

    elevate chmod 0644 /etc/logrotate.d/$SERVICE_NAME
}

# Регистрация в автозагрузке: update-rc.d (Debian/Devuan/MX),
# chkconfig (RH-подобные), либо симлинки вручную
enable_service() {
    if command -v update-rc.d >/dev/null 2>&1; then
        elevate update-rc.d "$SERVICE_NAME" defaults
    elif command -v chkconfig >/dev/null 2>&1; then
        elevate chkconfig --add "$SERVICE_NAME"
        elevate chkconfig "$SERVICE_NAME" on
    else
        local runlevel
        for runlevel in 2 3 4 5; do
            elevate ln -sf "../init.d/$SERVICE_NAME" "/etc/rc$runlevel.d/S20$SERVICE_NAME"
        done
        for runlevel in 0 1 6; do
            elevate ln -sf "../init.d/$SERVICE_NAME" "/etc/rc$runlevel.d/K20$SERVICE_NAME"
        done
    fi
}

disable_service() {
    if command -v update-rc.d >/dev/null 2>&1; then
        elevate update-rc.d -f "$SERVICE_NAME" remove 2>/dev/null || true
    fi

    if command -v chkconfig >/dev/null 2>&1; then
        elevate chkconfig --del "$SERVICE_NAME" 2>/dev/null || true
    fi

    local runlevel
    for runlevel in 0 1 2 3 4 5 6; do
        elevate rm -f "/etc/rc$runlevel.d/S20$SERVICE_NAME" "/etc/rc$runlevel.d/K20$SERVICE_NAME"
    done
}

# Функция для установки сервиса
install_service() {
    # Получение абсолютного пути
    local absolute_homedir_path
    absolute_homedir_path="$(realpath "$HOME_DIR_PATH")"

    echo "Создание sysvinit сервиса для автозагрузки..."
    render_sysvinit_script "$absolute_homedir_path" | elevate tee "$SERVICE_FILE" >/dev/null

    elevate chmod 0755 "$SERVICE_FILE"
    create_logrotate_conf
    enable_service

    # restart, чтобы перенастроенный conf.env применился и к уже работающему сервису
    if ! elevate "$SERVICE_FILE" restart >/dev/null; then
        echo "Сервис установлен, но не запустился. Лог: $LOG_FILE"
        return 1
    fi
    sleep 1
    check_nfqws_status
    echo "Сервис успешно установлен и запущен."
}

# Функция для удаления сервиса
remove_service() {
    echo "Удаление сервиса..."
    elevate "$SERVICE_FILE" stop 2>/dev/null || true
    disable_service
    elevate rm -f "$SERVICE_FILE"
    elevate rm -f "/etc/logrotate.d/$SERVICE_NAME"
    echo "Сервис удален."
}

# Функция для запуска сервиса
start_service() {
    echo "Запуск сервиса..."
    elevate "$SERVICE_FILE" start
    sleep 2
    check_nfqws_status
}

# Функция для остановки сервиса
stop_service() {
    echo "Остановка сервиса..."
    elevate "$SERVICE_FILE" stop
    echo "Сервис остановлен."
}

# Функция для перезапуска сервиса
restart_service() {
    echo "Перезапуск сервиса..."
    elevate "$SERVICE_FILE" restart
    sleep 2
    check_nfqws_status
}
