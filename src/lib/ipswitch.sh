#!/usr/bin/env bash

change_mode_ipset(){
    local ipset="$REPO_DIR/lists/ipset-all.txt"
    local bipset="$REPO_DIR/lists/ipset-all.txt.backup"
    if [[ $# != 1 ]]; then
        handle_error "Не приложен mode или приложено более двух аргументов"
    fi

    mode="$1"

    if [[ "$mode" == "None (Только Lists)" ]]; then
        rm -rf "$ipset"
        touch "$ipset"
        echo "Выбранный режим - $(get_mode_ipset)"
    elif [[ "$mode" == "Any (Весь траффик)" ]]; then
        if [ -f "$bipset" ]; then
            rm -rf "$ipset"
            cp "$bipset" "$ipset"
            echo "Выбранный режим - $(get_mode_ipset)"
            return 0
        fi
        handle_error "Не найден бекап, переустановите zapret стратегии"
    else
        if [ -f "$bipset" ]; then
            rm -rf "$bipset"
        fi
        cp "$ipset" "$bipset"
        echo "203.0.113.113/32" > "$ipset"
        echo "Выбранный режим - $(get_mode_ipset)"
        return 0
    fi
}

get_mode_ipset(){
    local ipset="$REPO_DIR/lists/ipset-all.txt"

    if grep -q "203.0.113.113" "$ipset"; then
        echo "None (Только Lists)"
    elif [[ $(wc -l < "$ipset") == 0 ]]; then
        echo "Any (Весь траффик)"
    else
        echo "Loaded (Только то что в Ipset)"
    fi
}