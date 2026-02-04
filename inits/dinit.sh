#!/usr/bin/env bash

# Константы
SERVICE_NAME="zapret_discord_youtube"
SERVICE_FILE="/etc/dinit.d/$SERVICE_NAME"
HOME_DIR_PATH="$(dirname "$0")"
MAIN_SCRIPT_PATH="$(dirname "$0")/../main_script.sh"   # Путь к основному скрипту
CONF_FILE="$(dirname "$0")/../conf.env"                # Путь к файлу конфигурации
STOP_SCRIPT="$(dirname "$0")/../stop_and_clean_nft.sh" # Путь к скрипту остановки и очистки nftables
CUSTOM_STRATEGIES_DIR="$HOME_DIR_PATH/custom-strategies"

# Функция для проверки существования conf.env и обязательных непустых полей
check_conf_file() {
    if [[ ! -f "$CONF_FILE" ]]; then
        return 1
    fi
    
    local required_fields=("interface" "gamefilter" "strategy")
    for field in "${required_fields[@]}"; do
        # Ищем строку вида field=Значение, где значение не пустое
        if ! grep -q "^${field}=[^[:space:]]" "$CONF_FILE"; then
            return 1
        fi
    done
    return 0
}

# Функция для интерактивного создания файла конфигурации conf.env
create_conf_file() {
    echo "Конфигурация отсутствует или неполная. Создаем новый конфиг."
    
    # 1. Выбор интерфейса
    local interfaces=("any" $(ls /sys/class/net))
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
    local repo_dir="$HOME_DIR_PATH/zapret-latest"
    
    
    # Собираем стратегии из репозитория и кастомной папки
    mapfile -t bat_files < <(find "$repo_dir" -maxdepth 1 -type f \( -name "*general*.bat" -o -name "*discord*.bat" \) 2>/dev/null)
    mapfile -t custom_bat_files < <(find "$CUSTOM_STRATEGIES_DIR" -maxdepth 1 -type f -name "*.bat" 2>/dev/null)
    
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
    cat <<EOF > "$CONF_FILE"
interface=$chosen_interface
gamefilter=$gamefilter_choice
strategy=$strategy_choice
EOF
    echo "Конфигурация записана в $CONF_FILE."
}

edit_conf_file() {
  echo "Изменение конфигурации..."
  create_conf_file
  echo "Конфигурация обновлена."
  
  # Проверка статуса способом динита
  SERVICE_STATUS=$(sudo dinitctl is-started "$SERVICE_NAME")

  # Если сервис активен, предлагаем перезапустить
  if [ ! -z "$SERVICE_STATUS" ]; then
    read -p "Сервис активен. Перезапустить сервис для применения новых настроек? (Y/n): " answer
    if [[ ${answer:-Y} =~ ^[Yy]$ ]]; then
      restart_service
    fi
  fi
}

# Функция для проверки статуса процесса nfqws
check_nfqws_status() {
    if pgrep -f "nfqws" >/dev/null; then
        echo "Демоны nfqws запущены."
    else
        echo "Демоны nfqws не запущены."
    fi
}

# Функция для проверки статуса сервиса
check_service_status() {
    SERVICE_EXISTS=$(ls /etc/dinit.d | grep $SERVICE_NAME)
    SERVICE_STATUS=$(sudo dinitctl is-started "$SERVICE_NAME")
    if [ -z "$SERVICE_EXISTS" ]; then
        echo "Статус: Сервис не установлен."
        return 1
    fi
    
    if [ ! -z "$SERVICE_STATUS" ]; then
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
    
    echo "Создание dinit сервиса для автозагрузки..."
    sudo bash -c "cat > $SERVICE_FILE" <<EOF
type = process
command = /usr/bin/bash /home/praef/zapret-discord-youtube-linux/main_script.sh -nointeractive
stop-command = /usr/bin/bash /home/praef/zapret-discord-youtube-linux/stop_and_clean_nft.sh
EOF
    sudo dinitctl enable "$SERVICE_NAME"
    echo "Сервис успешно установлен и запущен."
}

# Функция для удаления сервиса
remove_service() {
    echo "Удаление сервиса..."
    sudo dinitctl stop "$SERVICE_NAME"
    sudo dinitctl disable "$SERVICE_NAME"
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
    echo "Рестарт сервиса..."
    stop_service
    sleep 1
    start_service
}

# Основное меню управления
show_menu() {
  check_service_status
  local status=$?

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

# Запуск интерактивного меню
run_interactive() {
    show_menu
    echo ""
    read -p "Нажмите Enter для выхода..."
}

# Функция для получения доступных стратегий
strategies() {
    find "$(dirname "$0")/zapret-latest" $CUSTOM_STRATEGIES_DIR \
        -name "general*" -type f -printf "%f\n" 2>/dev/null | sort -u
}

# Функция для валидации и нормализации названия стратегии
# Возвращает 1, если не удалось валидировать название стратегии
#
# Примеры:
#   "general" -> echo "general.bat"
#   "alt11" -> echo "general_alt11.bat"
#   "not-a-strategy" -> return 1
normalize_strategy() {
    local s="$1"

    # Поиск совпадения с совпадением регистра
    local exact_match
    exact_match=$(strategies | grep -E "^(${s}|${s}\\.bat|general_${s}|general_${s}\\.bat)$")

    if [ -n "$exact_match" ]; then
        echo "$exact_match"
        return 0
    fi

    # Регистронезависимый поиск
    local case_insensitive_match
    case_insensitive_match=$(strategies | grep -i -E "^(${s}|${s}\\.bat|general_${s}|general_${s}\\.bat)$" | head -n1)

    if [ -n "$case_insensitive_match" ]; then
        echo "$case_insensitive_match"
        return 0
    fi

    return 1
}

# Функция для вывода доступных стратегий
show_strategies() {
    echo "Доступные стратегии:"
    echo
    strategies
}

# Функция для вывода текущей конфигурации
show_config() {
    if [ -f "$CONF_FILE" ]; then
        echo "Текущая конфигурация:"
        echo
        cat "$CONF_FILE"
        echo
    else
        echo "Файл конфигурации отсутствует"
    fi
}

# Функция для обновления конфигурации с рестартом сервиса.
update_config() {
    local strategy="$1"
    local interface="${2:-any}"
    local gamefilter="$3"

    # Валидация и нормализация названия стратегии
    local normalized_strategy
    if ! normalized_strategy=$(normalize_strategy "$strategy"); then
        echo "Несуществующая стратегия!"
        show_strategies
        exit 1
    fi

    if [[ "$interface" != "any" ]]; then
        interface_match=$(ls /sys/class/net | grep -E "^${interface}$")
        if [ ! -n "$interface_match" ]; then
            echo "Несуществующий интерфейс!"
            local interfaces=("any" $(ls /sys/class/net))
            echo "Доступные интерфейсы: ${interfaces[@]}"
            exit 1
        fi
    fi

    # TODO: Check interface.

    cat > "$CONF_FILE" << ENV
interface=${interface}
gamefilter=${gamefilter}
strategy=${normalized_strategy}
ENV

    echo "Конфигурация обновлена."
    show_config

    if [ "$RESTART_SERVICE" = true ]; then
        restart_service
    fi
}

# Помощь
show_usage() {
    echo "Usage:"
    echo "    $(basename "$0")         Run interactive service manager"
    echo
    echo "Commands:"
    echo "       --status        Show service status"
    echo "    -i --install       Install and start service"
    echo "    -R --remove        Remove service"
    echo "    -s --start         Start service"
    echo "    -S --stop          Stop service"
    echo "    -r --restart       Just restart the service"
    echo "    -l --strategies    List available strategies"
    echo "    -c --config        Show current config"
    echo "    -h --help          Show this help"
    echo
    echo "Update configuration:"
    echo "    $(basename "$0") [options] <STRATEGY> [INTERFACE]"
    echo
    echo "Options:"
    echo "    -g --gamefilter      Enable gamefilter"
    echo "    -n --norestart       Do not restart the service"
}

# Парсинг флагов
GAMEFILTER=false
RESTART_SERVICE=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --status) check_service_status
            exit 0
            ;;
        -i|--install)
            install_service
            exit 0
            ;;
        -R|--remove)
            remove_service
            exit 0
            ;;
        -s|--start)
            start_service
            exit 0
            ;;
        -S|--stop)
            stop_service
            exit 0
            ;;
        -r|--restart)
            restart_service
            exit 0
            ;;
        -l|--strategies)
            show_strategies
            exit 0
            ;;
        -c|--config)
            show_config
            exit 0
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        -g|--gamefilter)
            GAMEFILTER=true
            shift
            ;;
        -n|--norestart)
            RESTART_SERVICE=false
            shift
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

# Парсинг аргументов
case $# in
    0)
        # Run original interactive service manager
        run_interactive
        ;;
    1)
        update_config "$1" "any" "$GAMEFILTER"
        ;;
    2)
        update_config "$1" "$2" "$GAMEFILTER"
        ;;
    *)
        echo "Wrong arguments!"
        echo "Run '$(basename "$0") -h' for help"
        exit 1
        ;;
esac

