#!/usr/bin/env bash

# =============================================================================
# Общие константы для всех скриптов zapret-discord-youtube-linux
# =============================================================================

# Guard: проверяем что файл не был уже загружен
[[ -n "${_CONSTANTS_SH_LOADED:-}" ]] && return 0
_CONSTANTS_SH_LOADED=1

# Имя сервиса (используется во всех init-backends)
SERVICE_NAME="zapret_discord_youtube"

# Выбор бэкенда файрвола: auto, nftables, iptables
FIREWALL_BACKEND="auto"

# nftables настройки
NFT_TABLE="inet zapretunix"
NFT_CHAIN="output"
NFT_QUEUE_NUM=220
NFT_MARK="0x40000000"
NFT_RULE_COMMENT="Added by zapret script"

# iptables настройки
IPT_CHAIN="output"
IPT_TABLE="mangle"

# Ipset настройки
LOADED="Loaded (Ipset + Lists)"
ANY="Any (Весь траффик)"
NONE="None (Только Lists)"

# GameFilter
GAME_FILTER_PORTS="1024-65535"
GAME_FILTER_OFF_PORTS="12"

# Репозиторий со стратегиями
REPO_URL="https://github.com/Sergeydigl3/flowseal-strategies-backup"
MAIN_REPO_REV="c9baf981ee2eb33312de1745af8ed75c5d5e925e"

# Репозиторий zapret (для nfqws)
ZAPRET_REPO="bol-van/zapret"
ZAPRET_RECOMMENDED_VERSION="v72.9"
