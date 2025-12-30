#!/bin/bash

# ============================================
# Auto Tune Standalone для zapret
# Автоматический подбор стратегии для YouTube
# Работает из коробки - нужен только bash и curl
# ============================================

# Определяем директорию скрипта (работает при запуске из любого места)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT="$SCRIPT_DIR/main_script.sh"
STOP_SCRIPT="$SCRIPT_DIR/stop_and_clean_nft.sh"

#TODO: найти оптимальное время WAIT_TIME, CURL_TIMEOUT
# Время ожидания после запуска стратегии (секунды)
WAIT_TIME=2
# Таймаут для проверки YouTube (секунды)
CURL_TIMEOUT=2

#TODO: не хардкодить значения 14 и 6. Сделать автоматически по количеству файлов стратегий и подключений.
# Максимальные значения для параметров
MAX_STRATEGY=14   # Максимальный номер стратегии
MAX_CONNECTION=6  # Максимальный номер подключения

# Текущие значения
STRATEGY=1
CONNECTION=1

# Функция проверки доступности YouTube через curl
check_youtube() {
    echo -n "Проверяем YouTube... "
    
    local http_code
    http_code=$(curl -s --connect-timeout "$CURL_TIMEOUT" --max-time "$CURL_TIMEOUT" \
        -o /dev/null -w "%{http_code}" "https://youtube.com" 2>/dev/null)
    
    # HTTP коды 2xx и 3xx считаем успешными
    if [[ "$http_code" =~ ^[23] ]]; then
        echo "доступен (HTTP $http_code)"
        return 0  # Успех
    else
        echo "недоступен (HTTP $http_code)"
        return 1  # Неудача
    fi
}

# Функция для остановки текущей стратегии zapret
stop_zapret() {
    echo "Останавливаем текущую стратегию zapret..."
    sudo "$STOP_SCRIPT" 2>/dev/null
    sleep 1
}

# Функция для запуска main_script.sh с параметрами
run_main_script() {
    local strategy=$1
    local connection=$2
    echo "Запуск: main_script.sh (стратегия=$strategy, подключение=$connection)"
    # Передаём ответы на интерактивные вопросы через stdin
    # Запускаем в фоне чтобы не блокировать скрипт
    printf "y\n%d\n%d\n" "$strategy" "$connection" | "$MAIN_SCRIPT" &
    # Даём время на запуск
    sleep "$WAIT_TIME"
    return 0
}

# Функция для увеличения параметров
next_params() {
    # Увеличиваем номер стратегии
    STRATEGY=$((STRATEGY + 1))
    
    # Если стратегия превысила максимум, сбрасываем и увеличиваем подключение
    if [[ $STRATEGY -gt $MAX_STRATEGY ]]; then
        STRATEGY=1
        CONNECTION=$((CONNECTION + 1))
    fi
    
    # Проверяем, достигли ли максимума
    if [[ $CONNECTION -gt $MAX_CONNECTION ]]; then
        echo "❌ Достигнуты максимальные значения (стратегия=${MAX_STRATEGY}, подключение=${MAX_CONNECTION})."
        echo "Ни одна комбинация не сработала. Выход."
        exit 1
    fi
}

# ============================================
# Основная логика
# ============================================

echo ""
echo "╔════════════════════════════════════════╗"
echo "║     Auto Tune для zapret-youtube       ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Проверяем наличие curl
if ! command -v curl &> /dev/null; then
    echo "❌ Ошибка: curl не установлен. Установите: sudo apt install curl"
    exit 1
fi

# Проверяем наличие main_script.sh
if [[ ! -f "$MAIN_SCRIPT" ]]; then
    echo "❌ Ошибка: main_script.sh не найден в $SCRIPT_DIR"
    exit 1
fi

# Первая проверка
if ! check_youtube; then
    echo ""
    echo "YouTube недоступен. Начинаем подбор стратегии..."
    
    # Останавливаем zapret если уже запущен
    stop_zapret
    
    while true; do
        echo ""
        echo "=========================================="
        echo "Пробуем: стратегия=${STRATEGY}, подключение=${CONNECTION}"
        echo "=========================================="
        
        run_main_script $STRATEGY $CONNECTION
        
        # Проверяем YouTube после запуска стратегии
        if check_youtube; then
            echo ""
            echo "✓ YouTube отвечает! Стратегия=${STRATEGY}, подключение=${CONNECTION}"
            echo ""
            read -p "YouTube работает нормально? (y/n): " user_confirm
            if [[ "$user_confirm" =~ ^[Yy]$ ]]; then
                echo ""
                echo "✓ Отлично! Оставляем стратегию=${STRATEGY}, подключение=${CONNECTION}"
                echo ""
                echo "╔════════════════════════════════════════╗"
                echo "║         Настройка завершена!           ║"
                echo "╚════════════════════════════════════════╝"
                break
            else
                echo "Пользователь сообщил что не работает. Пробуем следующий вариант..."
                stop_zapret
                next_params
                continue
            fi
        fi
        
        echo "✗ YouTube всё ещё недоступен."
        
        # Останавливаем текущую стратегию перед следующей попыткой
        stop_zapret
        next_params
        
        echo "Переходим к следующей комбинации..."
    done
else
    echo ""
    echo "✓ YouTube уже доступен. Ничего делать не нужно."
fi

echo ""

