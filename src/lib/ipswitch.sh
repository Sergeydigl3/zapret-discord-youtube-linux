#!/usr/bin/env bash

SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")"
REPO_DIR="$SCRIPT_DIR/zapret-latest"
source "$SCRIPT_DIR/src/lib/constants.sh"
source "$SCRIPT_DIR/src/lib/common.sh"

# Глобальные переменные
ipset="$REPO_DIR/lists/ipset-all.txt"
bipset="$REPO_DIR/lists/ipset-all.txt.backup"

change_mode_ipset(){
    if [[ $# -lt 1 ]]; then
        echo "Не приложены аргументы"
        read -p "Нажмите Enter для продолжения..."
        return 0
    fi

    mode="$1"

    if [[ "$mode" == "Текущая версия конфигураций не поддерживается" ]]; then
        show_error "Текущая версия конфигураций не поддерживается. Для смены ipset режима вам следует поменять версию на более новую."
        return 0
    fi


    if [[ "$mode" == "$NONE" ]]; then
        switch_to_any
    elif [[ "$mode" == "$ANY" ]]; then
        switch_to_loaded
    else
        switch_to_none
    fi
}

switch_to_none(){
    if [ -f "$bipset" ]; then
        rm -rf "$bipset"
    fi
    cp "$ipset" "$bipset"
    echo "203.0.113.113/32" > "$ipset"
    echo "Выбранный режим - $(get_mode_ipset)"
    read -p "Нажмите Enter для продолжения..."
    return 0
}

switch_to_any(){
    rm -rf "$ipset"
    touch "$ipset"
    echo "Выбранный режим - $(get_mode_ipset)"
    read -p "Нажмите Enter для продолжения..."
    return 0
}

switch_to_loaded(){
    if [ -f "$bipset" ]; then
        rm -rf "$ipset"
        cp "$bipset" "$ipset"
        echo "Выбранный режим - $(get_mode_ipset)"
        read -p "Нажмите Enter для продолжения..."
        return 0
    fi
    echo "Не найден бекап, переустановите zapret стратегии."
    read -p "Нажмите Enter для продолжения..."
    return 0
}


get_mode_ipset(){
    local ipset="$REPO_DIR/lists/ipset-all.txt"

    if ! [ -d "$REPO_DIR/lists" ]; then
        echo "Текущая версия конфигураций не поддерживается"
        return 0
    fi

    if ! [ -f "$ipset" ]; then
        touch "$ipset"
    fi

    if grep -q "203.0.113.113/32" "$ipset"; then
        echo "$NONE"
    elif [[ $(wc -l < "$ipset") == 0 ]]; then
        echo "$ANY"
    else
        echo "$LOADED"
    fi
}