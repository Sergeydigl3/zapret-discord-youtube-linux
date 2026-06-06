#!/usr/bin/env bash

# NixOS backend: создаёт модуль /etc/nixos/zapret.nix, который
# ссылается на проект в его текущей директории, добавляет import
# в configuration.nix и выполняет nixos-rebuild switch.

MODULE_NAME="zapret.nix"
MODULE_PATH="/etc/nixos/$MODULE_NAME"
CONFIG_PATH="/etc/nixos/configuration.nix"

# Запускает nixos-rebuild switch с явной передачей NIX_PATH
_nixos_rebuild() {
    local nix_path="${NIX_PATH:-nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixpkgs:nixos=/nix/var/nix/profiles/per-user/root/channels/nixos}"
    elevate env "NIX_PATH=$nix_path" nixos-rebuild switch
}

check_service_status() {
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        echo "Статус: Сервис активен."
        return 2
    fi

    if [[ -f "$MODULE_PATH" ]]; then
        echo "Статус: Сервис не активен. Модуль NixOS установлен."
        return 3
    fi

    echo "Статус: Сервис не установлен."
    return 1
}

# Добавляет import в configuration.nix, если его там нет
_add_import_to_config() {
    if grep -q "zapret.nix" "$CONFIG_PATH" 2>/dev/null; then
        return 0
    fi

    local tmp
    tmp="$(mktemp)"

    elevate awk -v import="  ./$MODULE_NAME" '
    /imports[[:space:]]*=[[:space:]]*\[/ {
        if ($0 ~ /];/) {
            sub(/];/, sprintf("  %s\n  ];", import));
            print
        } else {
            print
            in_imports = 1
        }
        next
    }
    in_imports && /];/ {
        printf "    %s\n%s\n", import, $0
        in_imports = 0
        next
    }
    { print }
    ' "$CONFIG_PATH" > "$tmp" 2>/dev/null

    if [[ -s "$tmp" ]] && ! diff -q "$CONFIG_PATH" "$tmp" >/dev/null 2>&1; then
        elevate cp "$tmp" "$CONFIG_PATH"
        rm -f "$tmp"
        return 0
    fi

    elevate awk -v import="  imports = [ ./$MODULE_NAME ];" '
    /^}/ && !done {
        printf "%s\n\n%s\n", import, $0
        done = 1
        next
    }
    { print }
    ' "$CONFIG_PATH" > "$tmp" 2>/dev/null && elevate cp "$tmp" "$CONFIG_PATH"

    rm -f "$tmp"
}

# Убирает import из configuration.nix
_remove_import_from_config() {
    local tmp
    tmp="$(mktemp)"

    elevate awk '
    /zapret\.nix/ { next }
    { print }
    ' "$CONFIG_PATH" > "$tmp" 2>/dev/null && elevate cp "$tmp" "$CONFIG_PATH"

    rm -f "$tmp"
}

install_service() {
    local absolute_homedir_path
    absolute_homedir_path="$(realpath "$HOME_DIR_PATH")"

    echo "Установка сервиса для NixOS..."

    elevate tee "$MODULE_PATH" > /dev/null <<NIXEOF
{ config, pkgs, ... }:

{
  systemd.services.$SERVICE_NAME = {
    enable = true;
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    description = "zapret-discord-youtube DPI bypass";

    path = with pkgs; [ sudo git curl nftables iproute2 coreutils ];

    serviceConfig = {
      Type = "simple";
      WorkingDirectory = "$absolute_homedir_path";
      User = "root";
      ExecStart = ''
        \${pkgs.bash}/bin/bash $absolute_homedir_path/service.sh daemon
      '';
      ExecStop = ''
        \${pkgs.bash}/bin/bash $absolute_homedir_path/service.sh kill
      '';
      ExecStopPost = ''
        \${pkgs.coreutils}/bin/echo "Сервис завершён"
      '';
      PIDFile = "/run/$SERVICE_NAME.pid";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
NIXEOF

    _add_import_to_config

    echo "Запуск nixos-rebuild switch..."
    local rebuild_exit=0
    _nixos_rebuild || rebuild_exit=$?

    if [[ $rebuild_exit -eq 0 ]] || [[ $rebuild_exit -eq 4 ]]; then
        echo "Сервис установлен."
        echo "Проверьте статус: sudo systemctl status $SERVICE_NAME"
        if [[ $rebuild_exit -eq 4 ]]; then
            echo "Сервис не запустился — проверьте логи: sudo journalctl -u $SERVICE_NAME -n 50 --no-pager"
        fi
    else
        echo "nixos-rebuild switch не удался."
        echo "Проверьте /etc/nixos/configuration.nix и выполните вручную:"
        echo "  sudo nixos-rebuild switch"
        return 1
    fi
}

remove_service() {
    echo "Удаление сервиса..."

    _remove_import_from_config
    elevate rm -f "$MODULE_PATH"

    echo "Запуск nixos-rebuild switch..."
    local rebuild_exit=0
    _nixos_rebuild || rebuild_exit=$?

    if [[ $rebuild_exit -eq 0 ]] || [[ $rebuild_exit -eq 4 ]]; then
        echo "Сервис удалён."
    else
        echo "nixos-rebuild switch не удался."
        echo "Проверьте /etc/nixos/configuration.nix и выполните вручную:"
        echo "  sudo nixos-rebuild switch"
        return 1
    fi
}

start_service() {
    if elevate systemctl start "$SERVICE_NAME" 2>/dev/null; then
        echo "Сервис запущен."
        sleep 3
        check_nfqws_status
    else
        echo "Ошибка: Сервис не найден. Возможно, ещё не выполнен nixos-rebuild switch."
        return 1
    fi
}

stop_service() {
    elevate systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    echo "Сервис остановлен."
}

restart_service() {
    stop_service
    sleep 1
    start_service
}
