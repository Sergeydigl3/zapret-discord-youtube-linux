#!/usr/bin/env bash

handle_add_domains() {
  clear
  local file="$HOME_DIR_PATH/user-lists/list-exclude-user.txt"
  if [ ! -e "$file" ]; then
    echo "Ошибка: Файл не найден!"
    echo "Запустите: ./service.sh download-deps --default"
    echo "Это установит всё необходимое для zapret'а"
    echo "Переход в главное меню..."
    sleep 3
    run_interactive
    return 1
  fi

  local time_before=$(stat -c %Y "$file" 2>/dev/null || echo 0)

  echo "Запуск редактора nano"
  nano "$file"

  local time_after=$(stat -c %Y "$file" 2>/dev/null || echo 0)
  if [ "$time_before" -ne "$time_after" ]; then
    echo "Домены добавлены или изменены..."
  else
    echo "Изменений не обнаружено."
    echo "Переход в главное меню..."
    # поставьте с какой вам комфортно, хз :/
    sleep 0.7
    run_interactive
  fi

  echo "Запуск сервисного меню"
  echo ""
  echo "Сервисное меню:"
  show_service_menu
}
