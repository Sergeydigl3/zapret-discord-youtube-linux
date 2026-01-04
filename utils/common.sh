#!/usr/bin/env bash

# Общие утилиты и функции для всех скриптов

# Функция для логирования
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Функция для отладочного логирования
debug_log() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo "[DEBUG] $1"
    fi
}

# Функция для автоматического логирования команд (обертка)
# Использование: log_cmd "описание" команда аргументы
log_cmd() {
    local desc="$1"
    shift
    log "$desc: $*"
    "$@"
}

# Функция для выполнения команды с автоматическим логированием ошибок
safe_exec() {
    local desc="$1"
    shift
    if ! "$@" 2>/dev/null; then
        log "Ошибка при выполнении: $desc"
        return 1
    fi
    return 0
}

# Функция обработки ошибок
handle_error() {
    log "Ошибка: $1"
    exit 1
}

# Функция проверки зависимостей
check_dependencies() {
    local deps=("$@")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            handle_error "Не установлена утилита $dep"
        fi
    done
}

# Функция проверки существования conf.env и обязательных непустых полей
check_conf_file() {
    local conf_file="${1:-conf.env}"
    if [[ ! -f "$conf_file" ]]; then
        return 1
    fi
    
    local required_fields=("interface" "gamefilter" "strategy")
    for field in "${required_fields[@]}"; do
        if ! grep -q "^${field}=[^[:space:]]" "$conf_file"; then
            return 1
        fi
    done
    return 0
}

# Функция для интерактивного создания файла конфигурации conf.env
create_conf_file() {
    local conf_file="${1:-conf.env}"
    local script_dir="${2:-$(dirname "$0")}"
    
    echo "Конфигурация отсутствует или неполная. Создаем новый конфиг."
    
    # 1. Выбор интерфейса
    local interfaces=("any" $(ls /sys/class/net 2>/dev/null))
    if [ ${#interfaces[@]} -eq 0 ]; then
        handle_error "Не найдены сетевые интерфейсы"
    fi
    echo "Доступные сетевые интерфейсы:"
    select chosen_interface in "${interfaces[@]}"; do
        if [ -n "$chosen_interface" ]; then
            echo "Выбран интерфейс: $chosen_interface"
            break
        fi
        echo "Неверный выбор. Попробуйте еще раз."
    done

    # 2. Gamefilter
    read -p "Включить Gamefilter? [y/N] [n]: " enable_gamefilter
    if [[ "$enable_gamefilter" =~ ^[Yy1] ]]; then
        gamefilter_choice="true"
    else
        gamefilter_choice="false"
    fi
    
    # 3. Выбор стратегии
    local strategy_choice=""
    local repo_dir="$script_dir/zapret-latest"
    local custom_strategies_dir="$script_dir/custom-strategies"
    
    # Собираем стратегии из репозитория и кастомной папки
    mapfile -t bat_files < <(find "$repo_dir" -maxdepth 1 -type f \( -name "*general*.bat" -o -name "*discord*.bat" \) 2>/dev/null)
    mapfile -t custom_bat_files < <(find "$custom_strategies_dir" -maxdepth 1 -type f -name "*.bat" 2>/dev/null)
    
    if [ ${#bat_files[@]} -gt 0 ] || [ ${#custom_bat_files[@]} -gt 0 ]; then
        echo "Доступные стратегии (файлы .bat):"
        i=1
        
        # Показываем кастомные стратегии
        for bat in "${custom_bat_files[@]}"; do
            echo "  $i) $(basename "$bat") (кастомная)"
            ((i++))
        done
        
        # Показываем стратегии из репозитория
        for bat in "${bat_files[@]}"; do
            echo "  $i) $(basename "$bat")"
            ((i++))
        done
        
        read -p "Выберите номер стратегии: " bat_choice
        
        # Определяем выбранную стратегию
        if [ "$bat_choice" -le "${#custom_bat_files[@]}" ]; then
            strategy_choice="$(basename "${custom_bat_files[$((bat_choice-1))]}")"
        else
            strategy_choice="$(basename "${bat_files[$((bat_choice-1-${#custom_bat_files[@]}))]}")"
        fi
    else
        read -p "Файлы .bat не найдены. Введите название стратегии вручную: " strategy_choice
    fi
    
    # Записываем полученные значения в conf.env
    cat <<EOF > "$conf_file"
interface=$chosen_interface
gamefilter=$gamefilter_choice
strategy=$strategy_choice
EOF
    echo "Конфигурация записана в $conf_file."
}

# Функция для проверки статуса процесса nfqws
check_nfqws_status() {
    if pgrep -f "nfqws" >/dev/null; then
        echo "Демоны nfqws запущены."
    else
        echo "Демоны nfqws не запущены."
    fi
}

# Функция определения системы инициализации
detect_init_system() {
    if command -v systemctl >/dev/null 2>&1 && systemctl is-system-running >/dev/null 2>&1; then
        echo "systemd"
    elif command -v rc-service >/dev/null 2>&1 && [ -d /etc/init.d ]; then
        echo "openrc"
    elif [ -f /etc/init.d/functions ] || [ -d /etc/init.d ]; then
        echo "sysvinit"
    else
        echo "unknown"
    fi
}

# Функция определения firewall
detect_firewall() {
    if command -v nft >/dev/null 2>&1 && sudo nft list tables >/dev/null 2>&1; then
        echo "nftables"
    elif command -v iptables >/dev/null 2>&1 && sudo iptables -L -n >/dev/null 2>&1; then
        echo "iptables"
    else
        echo "none"
    fi
}

# Функция остановки процессов nfqws
stop_nfqws_processes() {
    log "Остановка всех процессов nfqws..."
    sudo pkill -f nfqws || log "Процессы nfqws не найдены"
}