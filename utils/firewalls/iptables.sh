#!/usr/bin/env bash

# Функции для работы с iptables

# Импортируем общие функции
source "$(dirname "$0")/../../common.sh"

# Очистка правил iptables
clear_iptables_rules() {
    log "Очистка правил iptables, добавленных скриптом..."
    
    # Проверка существования цепочки
    if sudo iptables -L "$IPT_CHAIN_NAME" -n >/dev/null 2>&1; then
        # Удаляем правила из OUTPUT, которые ссылаются на нашу цепочку
        sudo iptables -D OUTPUT -j "$IPT_CHAIN_NAME" 2>/dev/null || true
        
        # Очищаем и удаляем нашу цепочку
        sudo iptables -F "$IPT_CHAIN_NAME" 2>/dev/null || true
        sudo iptables -X "$IPT_CHAIN_NAME" 2>/dev/null || true
        
        log "Очистка iptables завершена."
    else
        log "Цепочка $IPT_CHAIN_NAME не найдена. Нечего очищать."
    fi
}

# Настройка правил iptables
setup_iptables_rules() {
    local interface="$1"
    shift
    local rules=("$@")
    
    log "Настройка iptables..."
    
    # Очистка существующих правил нашего скрипта
    sudo iptables -F "$IPT_CHAIN_NAME" 2>/dev/null || true
    sudo iptables -X "$IPT_CHAIN_NAME" 2>/dev/null || true
    
    # Создание новой цепочки
    sudo iptables -N "$IPT_CHAIN_NAME"
    
    # Опция интерфейса
    local interface_rule=""
    if [ -n "$interface" ] && [ "$interface" != "any" ]; then
        interface_rule="-o $interface"
    fi
    
    # Добавление правил
    for rule in "${rules[@]}"; do
        # Конвертируем nftables синтаксис в iptables
        if [[ "$rule" =~ ^([a-z]+)\ dport\ \{([0-9,-]+)\}\ counter\ queue\ num\ ([0-9]+) ]]; then
            local protocol="${BASH_REMATCH[1]}"
            local ports="${BASH_REMATCH[2]}"
            local queue="${BASH_REMATCH[3]}"
            
            # Конвертируем порты из формата {1,2,3-5} в -p tcp --dport 1 -p tcp --dport 2 ...
            IFS=',' read -ra port_array <<< "$ports"
            for port_spec in "${port_array[@]}"; do
                if [[ "$port_spec" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                    # Диапазон портов
                    sudo iptables -A "$IPT_CHAIN_NAME" $interface_rule -p "$protocol" --dport "${BASH_REMATCH[1]}:${BASH_REMATCH[2]}" -j NFQUEUE --queue-num "$queue"
                else
                    # Одиночный порт
                    sudo iptables -A "$IPT_CHAIN_NAME" $interface_rule -p "$protocol" --dport "$port_spec" -j NFQUEUE --queue-num "$queue"
                fi
            done
        fi
    done
    
    # Подключаем цепочку к OUTPUT
    sudo iptables -A OUTPUT -j "$IPT_CHAIN_NAME"
}

# Получение статуса iptables
get_iptables_status() {
    if sudo iptables -L "$IPT_CHAIN_NAME" -n >/dev/null 2>&1; then
        echo "iptables: цепочка $IPT_CHAIN_NAME существует"
        local rule_count=$(sudo iptables -L "$IPT_CHAIN_NAME" -n --line-numbers | wc -l)
        rule_count=$((rule_count - 2))  # Вычитаем заголовок и пустую строку
        echo "iptables: активных правил: $rule_count"
    else
        echo "iptables: цепочка $IPT_CHAIN_NAME не найдена"
    fi
}