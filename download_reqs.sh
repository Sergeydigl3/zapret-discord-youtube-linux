#!/usr/bin/env bash

set -eou pipefail

# Скрипт для загрузки бинарного файла nfqws и стратегий
# Использует utils/binary_downloader.sh для загрузки бинарника
# Клонирует репозиторий со стратегиями

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/zapret-latest"
REPO_URL="https://github.com/Flowseal/zapret-discord-youtube"
MAIN_REPO_REV="8a1885d7d06a098989c450bb851a9508d977725d"

# Импортируем общие функции
source "$SCRIPT_DIR/utils/common.sh"

# determine platform dir name
detect_platform_dir() {
    local os arch platform

    os=$(uname -s)
    arch=$(uname -m)

    case "$os" in
        Linux)
            case "$arch" in
                x86_64) platform="linux-x86_64" ;;
                i686|i386) platform="linux-x86" ;;
                armv7*|armv6*) platform="linux-arm" ;;
                aarch64) platform="linux-arm64" ;;
                mips64) platform="linux-mips64" ;;
                mips64el) platform="linux-mips64el" ;;
                mipsel) platform="linux-mipsel" ;;
                mips) platform="linux-mips" ;;
                ppc*) platform="linux-ppc" ;;
                *) handle_error "Unsupported Linux arch: $arch" ;;
            esac
            ;;
        Darwin)
            platform="mac64"
            ;;
        FreeBSD)
            platform="freebsd-x86_64"
            ;;
        MINGW*|MSYS*|CYGWIN*|Windows*)
            case "$arch" in
                x86_64) platform="windows-x86_64" ;;
                i686|i386) platform="windows-x86" ;;
                *) handle_error "Unsupported Windows arch: $arch" ;;
            esac
            ;;
        *)
            handle_error "Unsupported OS: $os"
            ;;
    esac

    echo "$platform"
}

# resolve tag
resolve_version() {
    local VERSION="latest"
    local REPO="bol-van/zapret"

    if [[ "$VERSION" != "latest" ]]; then
        echo "$VERSION"
        return
    fi

    local tag
    tag=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
        | grep -oP '"tag_name":\s*"\K(.*?)(?=")' || true)

    [[ -z "$tag" ]] && handle_error "Cannot determine latest release tag"
    echo "$tag"
}

# download archive
download_release() {
    local tag="$1"
    local REPO="bol-van/zapret"
    local BINARY_NAME="nfqws"
    local archive="zapret-${tag}.tar.gz"
    local url="https://github.com/${REPO}/releases/download/${tag}/${archive}"
    local tmp="/tmp/${archive}"

    log "Downloading: $url"
    curl -fL "$url" -o "$tmp" || handle_error "Download failed"
    echo "$tmp"
}

# extract + select binary
extract_binary() {
    local archive="$1"
    local platform_dir="$2"
    local BINARY_NAME="nfqws"
    local OUT_DIR="$SCRIPT_DIR"
    local tmpdir
    tmpdir=$(mktemp -d)

    log "Extracting archive..."
    tar -xzf "$archive" -C "$tmpdir" || handle_error "Extraction failed"

    local bin_path
    bin_path=$(find "$tmpdir" -type f -path "*/binaries/${platform_dir}/${BINARY_NAME}" | head -n1 || true)

    [[ -z "$bin_path" ]] && handle_error "Binary ${BINARY_NAME} not found for platform ${platform_dir}"

    cp "$bin_path" "${OUT_DIR}/${BINARY_NAME}"
    chmod +x "${OUT_DIR}/${BINARY_NAME}"

    log "Binary saved to: ${OUT_DIR}/${BINARY_NAME}"
    rm -rf "$tmpdir"
}

# Функция загрузки бинарного файла
download_binary() {
    log "Загрузка бинарного файла nfqws..."
    local tag platform archive

    platform=$(detect_platform_dir)
    log "Detected platform: $platform"

    tag=$(resolve_version)
    log "Using release tag: $tag"

    archive=$(download_release "$tag")
    extract_binary "$archive" "$platform"

    # Проверяем что файл создан
    if [[ ! -f "$SCRIPT_DIR/nfqws" ]]; then
        handle_error "Бинарный файл nfqws не был создан"
    fi

    chmod +x "$SCRIPT_DIR/nfqws"
    log "Бинарный файл успешно загружен"
}
# Функция загрузки стратегий
download_strategies() {
    log "Загрузка стратегий из репозитория..."

    if [[ -d "$REPO_DIR" ]]; then
        log "Репозиторий уже существует. Обновление..."
        cd "$REPO_DIR"
        git fetch origin
        git checkout "$MAIN_REPO_REV"
        cd "$SCRIPT_DIR"
    else
        log "Клонирование репозитория..."
        git clone "$REPO_URL" "$REPO_DIR" || handle_error "Ошибка при клонировании репозитория"
        cd "$REPO_DIR" && git checkout "$MAIN_REPO_REV" && cd "$SCRIPT_DIR"
    fi

    # Удаляем .git для экономии места
    rm -rf "$REPO_DIR/.git"

    # Запускаем скрипт переименования
    if [[ -f "$SCRIPT_DIR/rename_bat.sh" ]]; then
        chmod +x "$SCRIPT_DIR/rename_bat.sh"
        "$SCRIPT_DIR/rename_bat.sh" || handle_error "Ошибка при переименовании файлов"
    else
        log "Предупреждение: rename_bat.sh не найден"
    fi

    log "Стратегии успешно загружены"
}

# Основная функция
main() {
    check_dependencies git curl tar uname find
    download_binary
    download_strategies

    log "Загрузка завершена успешно!"
}

# Запуск
main "$@"