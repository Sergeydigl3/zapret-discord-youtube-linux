#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONSTANTS_FILE="$SCRIPT_DIR/../lib/constants.sh"
    
if [ ! -f "$CONSTANTS_FILE" ]; then
        echo "Файл constants.sh не найден!"
        exit 1
fi

. "$CONSTANTS_FILE"

GAMEFILTER_ON="1024-65535"
GAMEFILTER_OFF="12"

gamefilter_menu() {

    # Очистка экрана
    clear

    echo "========== Текущий статус GameFilter =========="

    TCP_STATUS="ВЫКЛЮЧЕН"
    UDP_STATUS="ВЫКЛЮЧЕН"

    if [ "$GAME_FILTER_TCP_PORTS" = "$GAMEFILTER_ON" ]; then
        TCP_STATUS="ВКЛЮЧЕН"
    fi

    if [ "$GAME_FILTER_UDP_PORTS" = "$GAMEFILTER_ON" ]; then
        UDP_STATUS="ВКЛЮЧЕН"
    fi

    echo "TCP: $TCP_STATUS ($GAME_FILTER_TCP_PORTS)"
    echo "UDP: $UDP_STATUS ($GAME_FILTER_UDP_PORTS)"

    echo ""

    # Общий статус
    if [ "$TCP_STATUS" = "ВКЛЮЧЕН" ] && [ "$UDP_STATUS" = "ВКЛЮЧЕН" ]; then
        echo "Общий статус: GameFilter включён для TCP + UDP"
    elif [ "$TCP_STATUS" = "ВКЛЮЧЕН" ]; then
        echo "Общий статус: GameFilter включён только для TCP"
    elif [ "$UDP_STATUS" = "ВКЛЮЧЕН" ]; then
        echo "Общий статус: GameFilter включён только для UDP"
    else
        echo "Общий статус: GameFilter выключен"
    fi

    echo "==============================================="
    echo ""
    echo "Что включить?"
    echo "1) Только TCP"
    echo "2) Только UDP"
    echo "3) TCP + UDP"
    echo "4) Выключить всё"
    echo "0) Отмена"

    read -p "Введите номер: " choice

    case "$choice" in
        1)
            sed -i "s/^GAME_FILTER_TCP_PORTS=.*/GAME_FILTER_TCP_PORTS=\"$GAMEFILTER_ON\"/" "$CONSTANTS_FILE"
            sed -i "s/^GAME_FILTER_UDP_PORTS=.*/GAME_FILTER_UDP_PORTS=\"$GAMEFILTER_OFF\"/" "$CONSTANTS_FILE"

            echo "GameFilter: TCP включен, UDP выключен"
            ;;

        2)
            sed -i "s/^GAME_FILTER_TCP_PORTS=.*/GAME_FILTER_TCP_PORTS=\"$GAMEFILTER_OFF\"/" "$CONSTANTS_FILE"
            sed -i "s/^GAME_FILTER_UDP_PORTS=.*/GAME_FILTER_UDP_PORTS=\"$GAMEFILTER_ON\"/" "$CONSTANTS_FILE"

            echo "GameFilter: UDP включен, TCP выключен"
            ;;

        3)
            sed -i "s/^GAME_FILTER_TCP_PORTS=.*/GAME_FILTER_TCP_PORTS=\"$GAMEFILTER_ON\"/" "$CONSTANTS_FILE"
            sed -i "s/^GAME_FILTER_UDP_PORTS=.*/GAME_FILTER_UDP_PORTS=\"$GAMEFILTER_ON\"/" "$CONSTANTS_FILE"

            echo "GameFilter: TCP и UDP включены"
            ;;

        4)
            sed -i "s/^GAME_FILTER_TCP_PORTS=.*/GAME_FILTER_TCP_PORTS=\"$GAMEFILTER_OFF\"/" "$CONSTANTS_FILE"
            sed -i "s/^GAME_FILTER_UDP_PORTS=.*/GAME_FILTER_UDP_PORTS=\"$GAMEFILTER_OFF\"/" "$CONSTANTS_FILE"

            echo "GameFilter полностью выключен"
            ;;

        0)
            echo "Отмена"
            return 0
            ;;

        *)
            echo "Неверный выбор!"
            return 1
            ;;
    esac
}

get_gamefilter_status() {

    local TCP_ENABLED=0
    local UDP_ENABLED=0

    if [ "$GAME_FILTER_TCP_PORTS" = "$GAMEFILTER_ON" ]; then
        local TCP_ENABLED=1
    fi

    if [ "$GAME_FILTER_UDP_PORTS" = "$GAMEFILTER_ON" ]; then
        local UDP_ENABLED=1
    fi

    # Возвращаем статус
    if [ "$TCP_ENABLED" -eq 1 ] && [ "$UDP_ENABLED" -eq 1 ]; then
        echo "TCP + UDP"
    elif [ "$TCP_ENABLED" -eq 1 ]; then
        echo "TCP"
    elif [ "$UDP_ENABLED" -eq 1 ]; then
        echo "UDP"
    else
        echo "DISABLED"
    fi
}