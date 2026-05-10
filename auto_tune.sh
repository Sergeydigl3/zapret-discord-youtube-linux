#!/bin/bash

VERSION="0.1"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[33m'
NC='\033[0m'

# Приветствие
echo -e "Unified Auto Tune ${GREEN}v$VERSION${NC}"
echo -e "Перед использованием ${RED}НАСТОЯТЕЛЬНО РЕКОМЕНДУЕТСЯ ОТКЛЮЧИТЬ ВСЕ СРЕДСТВА ОБХОДА БЛОКИРОВОК${NC}"
echo -e "Скрипт добавит домен в lists ${RED}автоматически${NC}\n"

# Переменные
## Пути
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_SCRIPT="$SCRIPT_DIR/service.sh"
RESULTS_FILE="$SCRIPT_DIR/auto_tune_results.txt"

## Протоколы
read -p "Введите домен: " domain
read -p "Проверять QUIC? (Y/N): " quic

## Данные
declare -a STRATEGIES=()
declare -a TCP_WORKED=()
declare -a QUIC_WORKED=()
declare -a BOTH_WORKED=()

# Функции
parse_strategies(){
    for strategy in $("$SERVICE_SCRIPT" strategy list | grep "\.bat"); do
        STRATEGIES+=("$strategy")
    done
}

add_domain_to_lists(){
    if [[ $domain == "youtube.com" || $domain == "discord.com" ]]; then
        return 0
    fi
    local path
    path=$(find "$SCRIPT_DIR/zapret-latest/" -name 'list-general.txt')
    if [[ -n "$path" && -f "$path" ]]; then
        if ! (cat "$path" | grep -qFw "$domain"); then
            echo "$domain" >> "$path"
        fi
    fi
}

check_configuration_work() {
    echo

    local result strategy exit_code 

    strategy=$1
    result=$(curl -s -o /dev/null -L -w "%{http_code}" --connect-timeout 3 --max-time 5 --tlsv1.3 --http2 "$domain")
    exit_code=$?

    if [[ $exit_code -eq 0 && "$result" =~ ^(200|301|302|307|308|404|403)$ ]]; then
        echo -e "Конфигурация $strategy ${GREEN}СРАБОТАЛА${NC} для домена $domain"
        TCP_WORKED+=("$strategy")
    else
        echo -e "Конфигурация $strategy ${RED}НЕ СРАБОТАЛА${NC} для домена $domain"
    fi

    if [[ $quic =~ ^[Yy]$ ]]; then
        result=$(curl -s -o /dev/null -L -w "%{http_code}" --connect-timeout 3 --max-time 5 --http3 "$domain")
        exit_code=$?
        if [[ $exit_code -eq 0 && "$result" =~ ^(200|301|302|307|308|404|403)$ ]]; then
            echo -e "Конфигурация $strategy ${GREEN}СРАБОТАЛА${NC} для домена $domain через QUIC"
            QUIC_WORKED+=("$strategy")
        else
            echo -e "Конфигурация $strategy ${RED}НЕ СРАБОТАЛА${NC} для домена $domain через QUIC"
        fi
    fi
}   

backup_config_file(){
    if [[ -f "$SCRIPT_DIR"/conf.env ]]; then
        mv "$SCRIPT_DIR"/conf.env "$SCRIPT_DIR"/conf.env.backup
    fi
}

set_configuration(){
    local strategy

    strategy=$1
    
    echo -e "interface=any\ngamefilter=false\nstrategy=$strategy" > "$SCRIPT_DIR"/conf.env
    "$SERVICE_SCRIPT" service install >> /dev/null 2>&1
    sleep 2
}

clear_configuration(){
    rm "$SCRIPT_DIR"/conf.env
    "$SERVICE_SCRIPT" service remove >> /dev/null 2>&1
}

restore_config_file(){
    if [[ -f "$SCRIPT_DIR"/conf.env.backup ]]; then
        mv "$SCRIPT_DIR"/conf.env.backup "$SCRIPT_DIR"/conf.env
    fi
}

get_quic_x_tcp(){
    for strategy in "${TCP_WORKED[@]}"; do
        if printf "%s\n" "${QUIC_WORKED[@]}" | grep -qx "$strategy" ; then
            BOTH_WORKED+=("$strategy")
        fi
    done
}

return_results(){
    echo
    echo "Результаты"
    echo -e "\t\t${BLUE}TCP${NC}"
    printf "%s\n" "${TCP_WORKED[@]}"
    if [[ $quic =~ ^[Yy]$ ]]; then
        get_quic_x_tcp
        echo
        echo -e "\t\t${GREEN}QUIC${NC}"
        printf "%s\n" "${QUIC_WORKED[@]}"
        echo
        echo -e "\t\t${YELLOW}QUIC & TCP${NC}"
        printf "%s\n" "${BOTH_WORKED[@]}"
    fi
}

write_to_file(){
    echo "TCP" > "$RESULTS_FILE"
    printf "%s\n" "${TCP_WORKED[@]}" >> "$RESULTS_FILE"
    if [[ $quic =~ ^[Yy]$ ]]; then
        echo "" >> "$RESULTS_FILE" 
        echo -e "QUIC" >> "$RESULTS_FILE"
        printf "%s\n" "${QUIC_WORKED[@]}" >> "$RESULTS_FILE"
        echo "" >> "$RESULTS_FILE"
        echo "QUIC & TCP" >> "$RESULTS_FILE" 
        printf "%s\n" "${BOTH_WORKED[@]}" >> "$RESULTS_FILE"
    fi
}

# Запуск программы
parse_strategies
backup_config_file
add_domain_to_lists

trap "return_results; write_to_file; restore_config_file; clear_configuration; exit" SIGINT
for strategy in "${STRATEGIES[@]}"; do
    set_configuration "$strategy"
    check_configuration_work "$strategy"
    clear_configuration
done

restore_config_file
return_results
write_to_file
