#!/usr/bin/env bash

# =============================================================================
# CLI: Главное меню и справка
# =============================================================================

# Главная справка
show_usage() {
  echo "Usage: $(basename "$0") <command> [options]"
  echo
  echo "Commands:"
  echo "    service        Manage the system service"
  echo "    config         Manage configuration"
  echo "    strategy       Manage strategies"
  echo "    download-deps  Download/update dependencies (zapret + strategies)"
  echo "    desktop        Manage desktop shortcut"
  echo "    run            Run interactively (without installing service)"
  echo "    setup-permissions  Setup NOPASSWD for nft/nfqws"
  echo
  echo "Internal commands:"
  echo "    daemon         Run zapret daemon (called by service)"
  echo "    kill           Stop nfqws and clear nftables"
  echo
  echo "Run '$(basename "$0") <command> --help' for command-specific help."
  echo
  echo "Examples:"
  echo "    $(basename "$0") service install"
  echo "    $(basename "$0") config set discord"
  echo "    $(basename "$0") strategy list"
  echo "    $(basename "$0") download-deps"
  echo "    $(basename "$0") desktop install"
  echo "    $(basename "$0") run -s discord"
}

# Основное меню управления
MENU_LOOP=0
show_menu() {
  clear
  big_zapret_art
  # zapret_cli_art # вроде выглядит даже по лучше

  # Строки COMMANDS
  # Статусы ipset и т.д
  local ipset_status=$(get_mode_ipset 2>/dev/null)
  local game_status=$(get_gamefilter_status 2>/dev/null)
  
  local ipset_line="Сменить режим ipset [Текущий - $ipset_status]"
  local game_line="Сменить режим gamefilter [Текущий - $game_status]"
  local first_line="Запустить (без установки сервиса)"
  local current_focus=""
  
  COMMANDS=(
    "$first_line"
    "Управление сервисом"
    "Изменить конфигурацию"
    "Управление зависимостями"
    "Управление ярлыком на рабочем столе"
    "Настроить работу без пароля"
    "$ipset_line"
    "$game_line"
    "Добавить домены в zapret"
    "Выход"
  )
  
  # Считаем перезапуски меню
  if [ "$MENU_LOOP" -eq 0 ]; then
    MENU_LOOP=1
    current_focus="$first_line"
  else
    current_focus="$ipset_line"
  fi

  # Выбор
  choice=$(gum choose --selected="$current_focus" "${COMMANDS[@]}" --header="~ Zapret CLI ~")

  [ -z "$choice" ] && exit 0
  case "$choice" in
    "Запустить"*)                  run_zapret_command; return 1 ;;
    "Управление сервисом"*)        show_service_menu; return 1 ;;
    "Изменить"*)                   create_conf_file; return 1 ;;
    "Управление зависимостями"*)   show_dependencies_menu; return 1 ;;
    "Управление ярлыком"*)         show_desktop_menu; return 1 ;;
    "Настроить"*)                  setup_permissions; return 1 ;;
    "Сменить режим ipset"*)        change_mode_ipset "$(get_mode_ipset)"; return 0 ;;
    "Сменить режим gamefilter"*)   gamefilter_menu; return 1 ;;
    "Добавить"*)                   handle_add_domains; return 1 ;;
    "Выход"*)                      clear ; zapret_cli_art ; exit 0 ;; # Выходим, выводим ascii art

    *) read -p "Действие не найдено!" ; return 1 ;;
  esac
}

# Запуск интерактивного меню
run_interactive() {
  while true; do
    show_menu
    res=$?
    if [ "$res" -eq 1 ]; then
      break
    fi
  done
}
