#!/bin/bash

VERSION="0.2"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[33m'
NC='\033[0m'

# Приветствие
clear
echo -e "Unified Auto Tune ${GREEN}v$VERSION${NC}\n"
echo -e "Перед использованием ${RED}НАСТОЯТЕЛЬНО РЕКОМЕНДУЕТСЯ ОТКЛЮЧИТЬ ВСЕ СРЕДСТВА ОБХОДА БЛОКИРОВОК${NC}"
echo -e "Скрипт предназначен для ${BLUE}поверхностной${NC} проверки стратегий"
echo -e "Для Youtube рекомендуется использовать ${GREEN}auto_tune.youtube.sh${NC}"
echo -e "Скрипт отключает ipset на время проверки ${RED}автоматически${NC}\n"

# Переменные

## Пути
SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SERVICE_SCRIPT="$SCRIPT_DIR/service.sh"
RESULTS_FILE="$SCRIPT_DIR/auto_tune_results.txt"

## Импорты
source "$SCRIPT_DIR/src/lib/constants.sh"
source "$SCRIPT_DIR/src/lib/ipswitch.sh" 

## Протоколы
read -r -p "Введите домен(ы) через пробел: " -a domains
read -p "Проверять QUIC? (Y/N): " quic

## Данные
declare -a STRATEGIES=()
declare -a TCP_WORKED=()
declare -a QUIC_WORKED=()
declare -a BOTH_WORKED=()
latest_mode=$(get_mode_ipset)

# Функции
parse_strategies(){
    for strategy in $("$SERVICE_SCRIPT" strategy list | grep "\.bat"); do
        STRATEGIES+=("$strategy")
    done
}

change_ipset(){
    local mode=$1

    if [[ "$mode" == "$ANY" ]]; then
        switch_to_any
    elif [[ "$mode" == "$NONE" ]]; then
        switch_to_none
    else
        switch_to_loaded
    fi
}

tcp_check() {
    local domain=$1
    local result exit_code
    result=$(curl -s -o /dev/null -L -w "%{http_code}" --connect-timeout 3 --max-time 5 --tlsv1.3 --http2 "$domain")
    exit_code=$?
    if [[ $exit_code -eq 0 && "$result" =~ ^(200|301|302|307|308|404|403)$ ]]; then
        return 0
    else
        return 1
    fi
}

quic_check() {
    local domain=$1
    local result exit_code
    result=$(curl -s -o /dev/null -L -w "%{http_code}" --connect-timeout 3 --max-time 5 --http3 "$domain")
    exit_code=$?
    if [[ $exit_code -eq 0 && "$result" =~ ^(200|301|302|307|308|404|403)$ ]]; then
        return 0
    else
        return 1
    fi
}

check_configuration_work() {
    echo

    local strategy globaltcpresults globalquicresults domain

    strategy=$1
    globaltcpresults=true
    globalquicresults=true

    for domain in "${domains[@]}"; do
        # TCP проверка
        if tcp_check "$domain"; then
            echo -e "Конфигурация $strategy ${GREEN}СРАБОТАЛА${NC} для домена $domain"
        else
            echo -e "Конфигурация $strategy ${RED}НЕ СРАБОТАЛА${NC} для домена $domain"
            globaltcpresults=false
        fi

        # QUIC проверка
        if [[ $quic =~ ^[Yy]$ ]]; then
            if quic_check "$domain"; then
                echo -e "Конфигурация $strategy ${GREEN}СРАБОТАЛА${NC} для домена $domain через QUIC"
            else
                echo -e "Конфигурация $strategy ${RED}НЕ СРАБОТАЛА${NC} для домена $domain через QUIC"
                globalquicresults=false
            fi
        fi
    done
    if [[ $globaltcpresults == true ]]; then TCP_WORKED+=("$strategy"); fi
    if [[ $globalquicresults == true ]]; then QUIC_WORKED+=("$strategy"); fi
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
change_ipset "$ANY"

trap 'change_ipset $latest_mode; return_results; write_to_file; clear_configuration; restore_config_file; exit' SIGINT
for strategy in "${STRATEGIES[@]}"; do
    set_configuration "$strategy"
    check_configuration_work "$strategy"
    clear_configuration
done

change_ipset "$latest_mode"
restore_config_file
return_results
write_to_file
