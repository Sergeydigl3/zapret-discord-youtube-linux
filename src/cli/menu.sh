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
show_menu() {
  clear
  echo "░▒▓████████▓▒░░▒▓██████▓▒░░▒▓███████▓▒░░▒▓███████▓▒░░▒▓████████▓▒░▒▓████████▓▒░ "
  echo "       ░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░         ░▒▓█▓▒░     "
  echo "     ░▒▓██▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░         ░▒▓█▓▒░     "
  echo "   ░▒▓██▓▒░  ░▒▓████████▓▒░▒▓███████▓▒░░▒▓███████▓▒░░▒▓██████▓▒░    ░▒▓█▓▒░     "
  echo " ░▒▓██▓▒░    ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░         ░▒▓█▓▒░     "
  echo "░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░         ░▒▓█▓▒░     "
  echo "░▒▓████████▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓████████▓▒░  ░▒▓█▓▒░     "
  echo ""
  COMMANDS=(
    "Запустить (без установки сервиса)"
    "Управление сервисом"
    "Изменить конфигурацию"
    "Управление зависимостями"
    "Управление ярлыком на рабочем столе"
    "Настроить работу без пароля"
    "Сменить режим ipset [Текущий - $(get_mode_ipset)]"
    "Сменить режим gamefilter [Текущий - $(get_gamefilter_status)]"
    "Добавить домены в zapret"
    "Выход"
  )
  choice=$(gum choose "${COMMANDS[@]}" --header="~ ZAPRET CLI ~ ")

  case $choice in
  "Запустить"*) run_zapret_command ;;
  "Управление сервисом"*) show_service_menu ;;
  "Изменить"*) create_conf_file ;;
  "Управление зависимостями"*) show_dependencies_menu ;;
  "Управление ярлыком"*) show_desktop_menu ;;
  "Настроить"*) setup_permissions ;;
  "Сменить режим ipset"*) change_mode_ipset "$(get_mode_ipset)" ;;
  "Сменить режим gamefilter"*) gamefilter_menu ;;
  "Добавить"*) handle_add_domains ;;
  "Выход"*) exit 0 ;;

  # Для тех кто будет что то дописывать проверьте не сливается ли ваша функция с другими
  # "Запустить"*) ... ;; -> "Запустить"*) ... ;;
  # "Запустить"*) ... ;; -> "Запустить {следующее слово т.к проверка идет по словам}"*) ... ;;

  *)
    # Будет странно если оно хоть раз случится
    read -p "Действие не найдено!"
    ;;
  esac
}

# Запуск интерактивного меню
run_interactive() {
  while true; do
    show_menu
  done
  echo ""
  read -p "Нажмите Enter для выхода..."
}
