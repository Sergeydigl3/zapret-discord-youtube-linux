#!/usr/bin/env bash

# Обновленный service.sh с поддержкой разных систем инициализации
# Сохраняет совместимость с существующим CLI интерфейсом

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Импортируем service_manager
if [[ -f "$SCRIPT_DIR/service_manager.sh" ]]; then
    source "$SCRIPT_DIR/service_manager.sh"
else
    echo "Ошибка: service_manager.sh не найден"
    exit 1
fi

# Запуск меню
show_menu
