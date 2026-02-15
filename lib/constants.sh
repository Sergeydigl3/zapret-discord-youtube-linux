#!/usr/bin/env bash

# =============================================================================
# Общие константы для всех скриптов zapret-discord-youtube-linux
# =============================================================================

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
MAIN_REPO_REV="7952e58ee8b068b731d55d2ef8f491fd621d6ff0"
