#!/usr/bin/env bash

# Константы
SERVICE_NAME="zapret_discord_youtube"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
HOME_DIR_PATH="$(dirname "$0")"
MAIN_SCRIPT_PATH="$(dirname "$0")/main_script.sh"   # Путь к основному скрипту
CONF_FILE="$(dirname "$0")/conf.env"                # Путь к файлу конфигурации
STOP_SCRIPT="$(dirname "$0")/stop_and_clean_nft.sh" # Путь к скрипту остановки и очистки nftables

# Функция для проверки существования conf.env и обязательных непустых полей
check_conf_file() {
    if [[ ! -f "$CONF_FILE" ]]; then
        return 1
    fi
    
    local required_fields=("interface" "auto_update" "strategy")
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
    
    # 2. Авто-обновление
    # read -p "Включить авто-обновление? (true/false) [false]: " auto_update_choice
    # if [[ "$auto_update_choice" != "true" ]]; then
    #     auto_update_choice="false"
    # fi
    auto_update_choice="false"
    
    # 3. Выбор стратегии
    local strategy_choice=""
    local repo_dir="$HOME_DIR_PATH/zapret-latest"
    if [[ -d "$repo_dir" ]]; then
        # Ищем .bat файлы, содержащие "general" или "discord", в папке репозитория (только в корне)
        mapfile -t bat_files < <(find "$repo_dir" -maxdepth 1 -type f -name "*general*.bat" -o -name "*discord*.bat")
        if [ ${#bat_files[@]} -gt 0 ]; then
            echo "Доступные стратегии (файлы .bat):"
            i=1
            for bat in "${bat_files[@]}"; do
                echo "  $i) $(basename "$bat")"
                ((i++))
            done
            read -p "Выберите номер стратегии: " bat_choice
            strategy_choice="$(basename "${bat_files[$((bat_choice-1))]}")"
        else
            read -p "Файлы .bat с 'general' или 'discord' не найдены. Введите название стратегии вручную: " strategy_choice
        fi
    else
        read -p "Папка репозитория не найдена. Введите название стратегии вручную: " strategy_choice
    fi
    
    
    # Записываем полученные значения в conf.env
    cat <<EOF > "$CONF_FILE"
interface=$chosen_interface
auto_update=$auto_update_choice
strategy=$strategy_choice
EOF
    echo "Конфигурация записана в $CONF_FILE."
}

edit_conf_file() {
  echo "Изменение конфигурации..."
  create_conf_file
  echo "Конфигурация обновлена."

  # Если сервис активен, предлагаем перезапустить
  if systemctl is-active --quiet "$SERVICE_NAME"; then
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
    
    echo "Создание systemd сервиса для автозагрузки..."
    sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=Custom Script Service
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

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable "$SERVICE_NAME"
    sudo systemctl start "$SERVICE_NAME"
    echo "Сервис успешно установлен и запущен."
}

# Функция для удаления сервиса
remove_service() {
    echo "Удаление сервиса..."
    sudo systemctl stop "$SERVICE_NAME"
    sudo systemctl disable "$SERVICE_NAME"
    sudo rm -f "$SERVICE_FILE"
    sudo systemctl daemon-reload
    echo "Сервис удален."
}

# Функция для запуска сервиса
start_service() {
    echo "Запуск сервиса..."
    sudo systemctl start "$SERVICE_NAME"
    echo "Сервис запущен."
    sleep 3
    check_nfqws_status
}

# Функция для остановки сервиса
stop_service() {
    echo "Остановка сервиса..."
    sudo systemctl stop "$SERVICE_NAME"
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

# Запуск меню
show_menu
