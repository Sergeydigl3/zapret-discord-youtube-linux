#!/usr/bin/env bash

# =============================
# CONFIG
# =============================
# "latest" or specific tag like "v72.5"
VERSION="latest"

REPO="bol-van/zapret"
BINARY_NAME="nfqws"
OUT_DIR="."



# =============================
# fail helper
# =============================
fail() {
    echo "ERROR: $*" >&2
    exit 1
}


# =============================
# deps
# =============================
check_deps() {
    command -v curl >/dev/null 2>&1 || fail "curl required"
    command -v tar  >/dev/null 2>&1 || fail "tar required"
    command -v uname >/dev/null 2>&1 || fail "uname required"
    command -v find >/dev/null 2>&1 || fail "find required"
}


# =============================
# determine platform dir name
# =============================
detect_platform_dir() {
    # English comments only
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
                *) fail "Unsupported Linux arch: $arch" ;;
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
                *) fail "Unsupported Windows arch: $arch" ;;
            esac
            ;;
        *)
            fail "Unsupported OS: $os"
            ;;
    esac

    echo "$platform"
}


# =============================
# resolve tag
# =============================
resolve_version() {
    if [[ "$VERSION" != "latest" ]]; then
        echo "$VERSION"
        return
    fi

    echo "Resolving latest release tag..." >&2
    local tag
    tag=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
        | grep -oP '"tag_name":\s*"\K(.*?)(?=")' || true)

    [[ -z "$tag" ]] && fail "Cannot determine latest release tag"
    echo "$tag"
}


# =============================
# download archive
# =============================
download_release() {
    local tag="$1"
    local archive="zapret-${tag}.tar.gz"
    local url="https://github.com/${REPO}/releases/download/${tag}/${archive}"
    local tmp="/tmp/${archive}"

    echo "Downloading: $url" >&2
    curl -fL "$url" -o "$tmp" || fail "Download failed"
    echo "$tmp"
}


# =============================
# extract + select binary
# =============================
extract_binary() {
    local archive="$1"
    local platform_dir="$2"
    local tmpdir
    tmpdir=$(mktemp -d)

    echo "Extracting archive..." >&2
    tar -xzf "$archive" -C "$tmpdir" || fail "Extraction failed"

    local bin_path
    bin_path=$(find "$tmpdir" -type f -path "*/binaries/${platform_dir}/${BINARY_NAME}" | head -n1 || true)

    [[ -z "$bin_path" ]] && fail "Binary ${BINARY_NAME} not found for platform ${platform_dir}"

    cp "$bin_path" "${OUT_DIR}/${BINARY_NAME}"
    chmod +x "${OUT_DIR}/${BINARY_NAME}"

    echo "Binary saved to: ${OUT_DIR}/${BINARY_NAME}" >&2
    rm -rf "$tmpdir"
}


# =============================
# MAIN
# =============================
main() {
    check_deps

    local tag platform archive

    platform=$(detect_platform_dir)
    echo "Detected platform: $platform" >&2

    tag=$(resolve_version)
    echo "Using release tag: $tag" >&2

    archive=$(download_release "$tag")
    extract_binary "$archive" "$platform"

    echo "Done." >&2
}

main "$@"
