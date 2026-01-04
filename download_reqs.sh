#!/usr/bin/env bash

# Скрипт для загрузки бинарного файла nfqws и стратегий
# Использует utils/binary_downloader.sh для загрузки бинарника
# Клонирует репозиторий со стратегиями

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY_DOWNLOADER="$SCRIPT_DIR/utils/binary_downloader.sh"
REPO_DIR="$SCRIPT_DIR/zapret-latest"
REPO_URL="https://github.com/Flowseal/zapret-discord-youtube"
MAIN_REPO_REV="8a1885d7d06a098989c450bb851a9508d977725d"
CUSTOM_DIR="$SCRIPT_DIR/custom-strategies"

# Импортируем общие функции
source "$SCRIPT_DIR/utils/common.sh"

# Глобальные переменные для стратегий
declare -a nft_rules=()
declare -a nfqws_params=()

# Функция загрузки бинарного файла
download_binary() {
    log "Загрузка бинарного файла nfqws..."
    
    if [[ ! -f "$BINARY_DOWNLOADER" ]]; then
        handle_error "Скрипт binary_downloader.sh не найден"
    fi
    
    chmod +x "$BINARY_DOWNLOADER"
    
    # Запускаем загрузчик
    cd "$SCRIPT_DIR" && "$BINARY_DOWNLOADER"
    
    if [[ $? -ne 0 ]]; then
        handle_error "Не удалось загрузить бинарный файл"
    fi
    
    # Проверяем что файл создан
    if [[ ! -f "$SCRIPT_DIR/nfqws" ]]; then
        handle_error "Бинарный файл nfqws не был создан"
    fi
    
    chmod +x "$SCRIPT_DIR/nfqws"
    log "Бинарный файл успешно загружен"
}

# Функция загрузки стратегий
download_strategies() {
    log "Загрузка стратегий из репозитория..."
    
    if [[ -d "$REPO_DIR" ]]; then
        log "Репозиторий уже существует. Обновление..."
        cd "$REPO_DIR"
        git fetch origin
        git checkout "$MAIN_REPO_REV"
        cd "$SCRIPT_DIR"
    else
        log "Клонирование репозитория..."
        git clone "$REPO_URL" "$REPO_DIR" || handle_error "Ошибка при клонировании репозитория"
        cd "$REPO_DIR" && git checkout "$MAIN_REPO_REV" && cd "$SCRIPT_DIR"
    fi
    
    # Удаляем .git для экономии места
    rm -rf "$REPO_DIR/.git"
    
    # Запускаем скрипт переименования
    if [[ -f "$SCRIPT_DIR/rename_bat.sh" ]]; then
        chmod +x "$SCRIPT_DIR/rename_bat.sh"
        "$SCRIPT_DIR/rename_bat.sh" || handle_error "Ошибка при переименовании файлов"
    else
        log "Предупреждение: rename_bat.sh не найден"
    fi
    
    log "Стратегии успешно загружены"
    }
    
    # Функция для поиска bat файлов внутри репозитория
    find_bat_files() {
        local pattern="$1"
        find "." -type f -name "$pattern" -print0
    }
    
    # Функция парсинга параметров из bat файла
    parse_bat_file() {
        local file="$1"
        local queue_num=0
        local bin_path="bin/"
        debug_log "Parsing .bat file: $file"
    
        while IFS= read -r line; do
            debug_log "Processing line: $line"
            
            [[ "$line" =~ ^[:space:]*:: || -z "$line" ]] && continue
            
            line="${line//%BIN%/$bin_path}"
            line="${line//%LISTS%/lists/}"
    
            # Обрабатываем GameFilter
            if [ "$USE_GAME_FILTER" = true ]; then
                # Заменяем %GameFilter% на порты
                line="${line//%GameFilter%/$GAME_FILTER_PORTS}"
            else
                # Удаляем GameFilter из списков портов
                line="${line//,%GameFilter%/}"
                line="${line//%GameFilter%,/}"
            fi
            
            if [[ "$line" =~ --filter-(tcp|udp)=([0-9,-]+)[[:space:]](.*?)(--new|$) ]]; then
                local protocol="${BASH_REMATCH[1]}"
                local ports="${BASH_REMATCH[2]}"
                local nfqws_args="${BASH_REMATCH[3]}"
                
                # Replace %LISTS% with 'lists/' in nfqws_args
                nfqws_args="${nfqws_args//%LISTS%/lists/}"
                nfqws_args="${nfqws_args//=^!/=!}"
                
                nft_rules+=("$protocol dport {$ports} counter queue num $queue_num bypass")
                nfqws_params+=("$nfqws_args")
                debug_log "Matched protocol: $protocol, ports: $ports, queue: $queue_num"
                debug_log "NFQWS parameters for queue $queue_num: $nfqws_args"
                
                ((queue_num++))
            fi
        done < <(grep -v "^@echo" "$file" | grep -v "^chcp" | tr -d '\r')
    }
    
    # Функция для выбора стратегии
    select_strategy() {
        local strategy="$1"
        local nointeractive="$2"
        
        # Сначала собираем кастомные файлы
        local custom_files=()
        if [ -d "$CUSTOM_DIR" ]; then
            cd "$CUSTOM_DIR" && custom_files=($(ls *.bat 2>/dev/null)) && cd "$SCRIPT_DIR"
        fi
    
        cd "$REPO_DIR" || handle_error "Не удалось перейти в директорию $REPO_DIR"
        
        if [ "$nointeractive" = true ]; then
            if [ ! -f "$strategy" ] && [ ! -f "../$CUSTOM_DIR/$strategy" ]; then
                handle_error "Указанный .bat файл стратегии $strategy не найден"
            fi
            # Проверяем, где лежит файл, чтобы распарсить
            [ -f "$strategy" ] && parse_bat_file "$strategy" || parse_bat_file "../$CUSTOM_DIR/$strategy"
            cd "$SCRIPT_DIR"
            return
        fi
        
        # Собираем стандартные файлы
        local IFS=$'\n'
        local repo_files=($(find_bat_files "general*.bat" | xargs -0 -n1 echo) $(find_bat_files "discord.bat" | xargs -0 -n1 echo))
        
        # Объединяем списки (кастомные будут первыми)
        local bat_files=("${custom_files[@]}" "${repo_files[@]}")
        
        if [ ${#bat_files[@]} -eq 0 ]; then
            cd "$SCRIPT_DIR"
            handle_error "Не найдены подходящие .bat файлы"
        fi
    
        echo "Доступные стратегии:"
        select strategy_choice in "${bat_files[@]}"; do
            if [ -n "$strategy_choice" ]; then
                log "Выбрана стратегия: $strategy_choice"
                
                # Определяем полный путь для парсера перед выходом из папки
                local final_path=""
                if [ -f "$strategy_choice" ]; then
                    final_path="$REPO_DIR/$strategy_choice"
                else
                    final_path="$REPO_DIR/../$CUSTOM_DIR/$strategy_choice"
                fi
                
                cd "$SCRIPT_DIR"
                parse_bat_file "$final_path"
                break
            fi
            echo "Неверный выбор. Попробуйте еще раз."
        done
    }
    
    # Функция для загрузки и подготовки всех компонентов
    download_all() {
        log "Начало загрузки бинарников и стратегий..."
        
        check_dependencies git curl tar
        download_binary
        download_strategies
        
        log "Загрузка завершена успешно!"
    }
    
    # Функция для выбора стратегии и сохранения конфигурации
    setup_strategy() {
        local strategy="${1:-}"
        local nointeractive="${2:-false}"
        local gamefilter="${3:-false}"
        
        # Устанавливаем флаг GameFilter
        if [ "$gamefilter" = true ]; then
            USE_GAME_FILTER=true
            GAME_FILTER_PORTS="1024-65535"
            log "GameFilter включен"
        else
            USE_GAME_FILTER=false
            log "GameFilter выключен"
        fi
        
        # Выбираем стратегию
        if [ -n "$strategy" ]; then
            select_strategy "$strategy" "$nointeractive"
        else
            select_strategy "" "false"
        fi
        
        log "Стратегия настроена"
    }
    
    # Функция для сохранения конфигурации в файл
    save_config() {
        local interface="$1"
        local gamefilter="$2"
        local strategy="$3"
        local conf_file="${4:-conf.env}"
        
        cat <<EOF > "$conf_file"
    interface=$interface
    gamefilter=$gamefilter
    strategy=$strategy
    EOF
        log "Конфигурация записана в $conf_file"
    }
    
    # Основная функция
    main() {
        local mode="download"
        local strategy=""
        local nointeractive=false
        local gamefilter=false
        local interface="any"
        local conf_file="conf.env"
        
        # Парсинг аргументов
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --download-only)
                    mode="download"
                    shift
                    ;;
                --setup-strategy)
                    mode="setup"
                    shift
                    if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
                        strategy="$1"
                        shift
                    fi
                    ;;
                --nointeractive)
                    nointeractive=true
                    shift
                    ;;
                --gamefilter)
                    gamefilter=true
                    shift
                    ;;
                --interface)
                    interface="$2"
                    shift 2
                    ;;
                --conf-file)
                    conf_file="$2"
                    shift 2
                    ;;
                --help)
                    echo "Использование: $0 [опции]"
                    echo "Опции:"
                    echo "  --download-only      Только загрузить бинарники и стратегии"
                    echo "  --setup-strategy [file]  Настроить стратегию (можно указать файл)"
                    echo "  --nointeractive      Неинтерактивный режим"
                    echo "  --gamefilter         Включить GameFilter"
                    echo "  --interface [name]   Указать интерфейс (по умолчанию: any)"
                    echo "  --conf-file [path]   Путь к файлу конфигурации (по умолчанию: conf.env)"
                    echo "  --help               Показать эту справку"
                    exit 0
                    ;;
                *)
                    echo "Неизвестный параметр: $1"
                    echo "Используйте --help для справки"
                    exit 1
                    ;;
            esac
        done
        
        case "$mode" in
            download)
                download_all
                echo ""
                echo "Загрузка завершена. Для настройки стратегии используйте:"
                echo "  sudo bash $0 --setup-strategy [--nointeractive] [--gamefilter]"
                ;;
            setup)
                if [ "$nointeractive" = true ]; then
                    # В неинтерактивном режиме требуется conf.env
                    if [ ! -f "$conf_file" ]; then
                        handle_error "Файл конфигурации $conf_file не найден в неинтерактивном режиме"
                    fi
                    source "$conf_file"
                    if [ -z "$interface" ] || [ -z "$gamefilter" ] || [ -z "$strategy" ]; then
                        handle_error "Отсутствуют обязательные параметры в $conf_file"
                    fi
                    setup_strategy "$strategy" true "$([ "$gamefilter" = "true" ] && echo true || echo false)"
                    # Сохраняем конфиг (обновляем)
                    save_config "$interface" "$gamefilter" "$strategy" "$conf_file"
                else
                    # Интерактивный режим
                    setup_strategy "$strategy" false "$gamefilter"
                    
                    # Выбор интерфейса
                    local interfaces=("any" $(ls /sys/class/net 2>/dev/null))
                    if [ ${#interfaces[@]} -eq 0 ]; then
                        handle_error "Не найдены сетевые интерфейсы"
                    fi
                    echo "Доступные сетевые интерфейсы:"
                    select chosen_interface in "${interfaces[@]}"; do
                        if [ -n "$chosen_interface" ]; then
                            log "Выбран интерфейс: $chosen_interface"
                            interface="$chosen_interface"
                            break
                        fi
                        echo "Неверный выбор. Попробуйте еще раз."
                    done
                    
                    # Сохраняем конфиг
                    save_config "$interface" "$gamefilter" "${strategy:-$(basename "$(find "$REPO_DIR" -name "*.bat" | head -1)")}" "$conf_file"
                fi
                echo ""
                echo "Настройка завершена. Теперь можно запустить:"
                echo "  sudo bash main_script.sh"
                ;;
        esac
    }
    
    # Запуск
    main "$@"