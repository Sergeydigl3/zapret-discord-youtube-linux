#!/usr/bin/env bash

# =============================================================================
# Общие константы для всех скриптов zapret-discord-youtube-linux
# =============================================================================

# Guard: проверяем что файл не был уже загружен
[[ -n "${_CONSTANTS_SH_LOADED:-}" ]] && return 0
_CONSTANTS_SH_LOADED=1

# Имя сервиса (используется во всех init-backends)
SERVICE_NAME="zapret_discord_youtube"

# nftables настройки
NFT_TABLE="inet zapretunix"
NFT_CHAIN="output"
NFT_QUEUE_NUM=220
NFT_MARK="0x40000000"
NFT_RULE_COMMENT="Added by zapret script"

# Ipset настройки
LOADED="Loaded (Ipset + Lists)"
ANY="Any (Весь траффик)"
NONE="None (Только Lists)"

# GameFilter
GAME_FILTER_PORTS="1024-65535"
GAME_FILTER_TCP_PORTS="12"
GAME_FILTER_UDP_PORTS="1024-65535"

# Репозиторий со стратегиями
REPO_URL="https://github.com/Flowseal/zapret-discord-youtube"
MAIN_REPO_REV="4f8d81b74228dd5dc11dae3fa32337b9eaa16669"

# Репозиторий zapret (для nfqws)
ZAPRET_REPO="bol-van/zapret"
ZAPRET_RECOMMENDED_VERSION="v72.9"
