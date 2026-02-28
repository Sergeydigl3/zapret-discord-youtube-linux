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

# GameFilter
GAME_FILTER_PORTS="1024-65535"

# Репозиторий со стратегиями
REPO_URL="https://github.com/Flowseal/zapret-discord-youtube"
MAIN_REPO_REV="cb9aed09449e1c51a9108c7989717c7c98a14301"

# Репозиторий zapret (для nfqws)
ZAPRET_REPO="bol-van/zapret"
ZAPRET_RECOMMENDED_VERSION="v72.9"
