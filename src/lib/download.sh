#!/usr/bin/env bash

# =============================================================================
# Функции для скачивания зависимостей (nfqws, стратегии)
# =============================================================================

# Guard: проверяем что файл не был уже загружен
[[ -n "${_DOWNLOAD_SH_LOADED:-}" ]] && return 0
_DOWNLOAD_SH_LOADED=1

# Подключаем зависимости
source "$(dirname "${BASH_SOURCE[0]}")/constants.sh"
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# -----------------------------------------------------------------------------
# Скачивание nfqws бинарника
# -----------------------------------------------------------------------------

# Определение платформы для скачивания бинарника
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
                *) handle_error "Неподдерживаемая архитектура Linux: $arch" ;;
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
                *) handle_error "Неподдерживаемая архитектура Windows: $arch" ;;
            esac
            ;;
        *)
            handle_error "Неподдерживаемая ОС: $os"
            ;;
    esac

    echo "$platform"
}

# Получение последней версии zapret из GitHub
resolve_zapret_version() {
    local version="${1:-latest}"

    if [[ "$version" != "latest" ]]; then
        echo "$version"
        return
    fi

    local tag
    tag=$(curl -fsSL "https://api.github.com/repos/${ZAPRET_REPO}/releases/latest" \
        | grep -oP '"tag_name":\s*"\K(.*?)(?=")' || true)

    [[ -z "$tag" ]] && handle_error "Не удалось определить последний релиз zapret"
    echo "$tag"
}

# Скачивание релиза zapret в рабочий каталог
# $1 - тег релиза, $2 - рабочий каталог
# Возвращает путь к скачанному архиву
download_zapret_release() {
    local tag="$1"
    local work_dir="$2"
    local archive="zapret-${tag}.tar.gz"
    local url="https://github.com/${ZAPRET_REPO}/releases/download/${tag}/${archive}"
    local tmp="${work_dir}/${archive}"

    log "Скачивание zapret: $url" >&2
    curl -fL "$url" -o "$tmp" || handle_error "Ошибка при скачивании zapret"
    echo "$tmp"
}

# Хеш файла: sha256sum из coreutils, shasum на *BSD/macOS
_sha256_of() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        return 1
    fi
}

# Проверка бинарника по sha256sum.txt из релиза zapret
# $1 - файл, $2 - каталог платформы, $3 - тег релиза, $4 - рабочий каталог
# Возвращает 0, если хеш совпал (или проверить нечем), и 1 при несовпадении
verify_nfqws_checksum() {
    local binary="$1"
    local platform_dir="$2"
    local tag="$3"
    local work_dir="$4"
    local binary_name="nfqws"
    local sums="${work_dir}/sha256sum.txt"
    local sums_url="https://github.com/${ZAPRET_REPO}/releases/download/${tag}/sha256sum.txt"

    local actual
    if ! actual=$(_sha256_of "$binary"); then
        log "ПРЕДУПРЕЖДЕНИЕ: нет sha256sum/shasum, проверка контрольной суммы пропущена" >&2
        return 0
    fi

    if ! curl -fsSL "$sums_url" -o "$sums"; then
        log "ПРЕДУПРЕЖДЕНИЕ: не удалось скачать sha256sum.txt для ${tag}, проверка пропущена" >&2
        return 0
    fi

    local expected
    expected=$(awk -v suffix="/binaries/${platform_dir}/${binary_name}" \
        'length($2) >= length(suffix) && substr($2, length($2) - length(suffix) + 1) == suffix {print $1; exit}' \
        "$sums")

    if [[ -z "$expected" ]]; then
        log "ПРЕДУПРЕЖДЕНИЕ: хеш для binaries/${platform_dir}/${binary_name} не найден в sha256sum.txt, проверка пропущена" >&2
        return 0
    fi

    if [[ "$actual" != "$expected" ]]; then
        log "Ошибка: sha256 ${binary_name} ($actual) не совпадает с релизом ($expected)" >&2
        return 1
    fi

    log "Контрольная сумма ${binary_name} совпадает с sha256sum.txt релиза ${tag}" >&2
    return 0
}

# Извлечение бинарника nfqws из архива
# $1 - архив, $2 - каталог платформы, $3 - каталог установки, $4 - рабочий каталог
extract_nfqws_binary() {
    local archive="$1"
    local platform_dir="$2"
    local out_dir="$3"
    local work_dir="${4:-}"
    local binary_name="nfqws"
    local extract_dir

    if [[ -n "$work_dir" ]]; then
        extract_dir="${work_dir}/extract"
    else
        extract_dir=$(mktemp -d)
    fi
    mkdir -p "$extract_dir"

    log "Извлечение архива zapret..." >&2
    tar -xzf "$archive" -C "$extract_dir" || handle_error "Ошибка при извлечении архива"

    local bin_path
    bin_path=$(find "$extract_dir" -type f -path "*binaries/${platform_dir}/${binary_name}" | head -n1 || true)

    [[ -z "$bin_path" ]] && handle_error "Бинарник ${binary_name} не найден для платформы ${platform_dir}"

    cp "$bin_path" "${out_dir}/${binary_name}"
    chmod +x "${out_dir}/${binary_name}"

    log "Бинарник сохранён: ${out_dir}/${binary_name}" >&2
}

# Главная функция скачивания nfqws
# Требует: BASE_DIR или NFQWS_PATH
download_nfqws() {
    local version="${1:-latest}"
    local out_dir="${BASE_DIR:-$(dirname "$NFQWS_PATH")}"
    local platform tag work_dir archive

    log "Скачивание nfqws (версия: $version)..." >&2

    platform=$(detect_platform_dir) || handle_error "Не удалось определить платформу"
    log "Определена платформа: $platform" >&2

    tag=$(resolve_zapret_version "$version") || handle_error "Не удалось определить версию релиза zapret"
    log "Используется версия релиза: $tag" >&2

    work_dir=$(mktemp -d "${TMPDIR:-/tmp}/zapret-install.XXXXXX") || \
        handle_error "Не удалось создать временный каталог"

    archive=$(download_zapret_release "$tag" "$work_dir") || \
        handle_error "Ошибка при скачивании zapret ${tag}"
    extract_nfqws_binary "$archive" "$platform" "$out_dir" "$work_dir"

    if ! verify_nfqws_checksum "${out_dir}/nfqws" "$platform" "$tag" "$work_dir"; then
        rm -f "${out_dir}/nfqws"
        rm -rf "$work_dir"
        handle_error "Контрольная сумма nfqws не совпала с sha256sum.txt релиза ${tag}. Установка прервана."
    fi

    rm -rf "$work_dir"

    # Проверяем что файл создан
    if [[ ! -f "$out_dir/nfqws" ]]; then
        show_error "Бинарник nfqws не был создан"
        return 0
    fi

    log "Бинарник nfqws успешно загружен" >&2
}

# -----------------------------------------------------------------------------
# Получение списка версий из GitHub
# -----------------------------------------------------------------------------

# Получение списка git тегов из удалённого репозитория
get_git_tags() {
    local repo_url="$1"

    # Получаем список тегов через git ls-remote, сортируем от новых к старым
    git ls-remote --tags --sort=-v:refname "$repo_url" 2>/dev/null | \
        grep -v '\^{}' | \
        awk '{print $2}' | \
        sed 's|refs/tags/||' || echo ""
}

# -----------------------------------------------------------------------------
# Интерактивный выбор версий
# -----------------------------------------------------------------------------

# Интерактивный выбор версии zapret (nfqws)
# Записывает результат в переменную $selected_zapret_version
select_zapret_version_interactive() {
    clear
    echo "Выберите версию zapret (nfqws):"
    echo ""
    echo "1) $ZAPRET_RECOMMENDED_VERSION (Рекомендованная, протестированная)"
    echo "2) latest (Последняя доступная версия)"
    echo "3) Ввести версию вручную"
    echo "4) Выбрать из доступных версий"
    echo "5) Пропустить"
    echo ""

    read -p "Ваш выбор [1-5]: " choice

    case $choice in
        1)
            selected_zapret_version="$ZAPRET_RECOMMENDED_VERSION"
            ;;
        2)
            selected_zapret_version="latest"
            ;;
        3)
            read -p "Введите версию (тег): " selected_zapret_version
            if [[ -z "$selected_zapret_version" ]]; then
                show_error "Версия не может быть пустой!"
                select_zapret_version_interactive
            fi
            ;;
        4)
            echo "Загрузка списка версий..."
            local tags
            tags=$(get_git_tags "https://github.com/${ZAPRET_REPO}")

            if [[ -z "$tags" ]]; then
                show_error "Теги не найдены в репозитории"
                return 0
            fi

            # Преобразуем в массив
            local tag_array=()
            while IFS= read -r line; do
                tag_array+=("$line")
            done <<< "$tags"

            if [[ ${#tag_array[@]} -eq 0 ]]; then
                show_error "Теги не найдены в репозитории"
                return 0
            fi

            # Формируем финальный список с рекомендованной версией первой
            local final_array=()

            # Добавляем рекомендованную версию первой с меткой
            final_array+=("$ZAPRET_RECOMMENDED_VERSION (рекомендованная)")

            # Добавляем остальные версии, пропуская рекомендованную если встретим
            for tag in "${tag_array[@]}"; do
                if [[ "$tag" != "$ZAPRET_RECOMMENDED_VERSION" ]]; then
                    final_array+=("$tag")
                fi
            done

            echo ""
            echo "Доступные версии (рекомендованная первая, остальные от новых к старым):"
            select tag in "${final_array[@]}"; do
                if [[ -n "$tag" ]]; then
                    # Убираем метку "(рекомендованная)" если есть
                    selected_zapret_version="${tag% (рекомендованная)}"
                    echo "Выбрана версия: $selected_zapret_version"
                    break
                fi
                show_error "Неверный выбор. Попробуйте еще раз."
            done
            ;;
        5)
            echo -e "Пропуск загрузки nfqws\n"
            return 0
            ;;
        *)
            show_error "Такого варианта нет"
            select_zapret_version_interactive
            ;;
    esac
}

# Интерактивный выбор версии стратегий
# Записывает результат в переменную $selected_strat_version
select_strategy_version_interactive() {
    clear
    echo "Выберите версию стратегий:"
    echo ""
    echo "1) $MAIN_REPO_REV (Рекомендованная, протестированная)"
    echo "2) Ввести хеш/тег вручную"
    echo "3) Выбрать из доступных тегов"
    echo ""

    read -p "Ваш выбор [1-3]: " choice

    case $choice in
        1)
            selected_strat_version="$MAIN_REPO_REV"
            ;;
        2)
            read -p "Введите хеш коммита или тег: " selected_strat_version
            if [[ -z "$selected_strat_version" ]]; then
                show_error "Версия не может быть пустой!"
                select_strategy_version_interactive
            fi
            ;;
            
        3)
            echo "Загрузка списка тегов..."
            local tags
            tags=$(get_git_tags "$REPO_URL")

            if [[ -z "$tags" ]]; then
                show_error "Теги не найдены в репозитории"
                select_strategy_version_interactive
            fi

            # Преобразуем в массив
            local tag_array=()
            while IFS= read -r line; do
                tag_array+=("$line")
            done <<< "$tags"

            if [[ ${#tag_array[@]} -eq 0 ]]; then
                show_error "Теги не найдены в репозитории"
                select_strategy_version_interactive
            fi

            echo ""
            echo "Доступные теги (от новых к старым):"
            select tag in "${tag_array[@]}"; do
                if [[ -n "$tag" ]]; then
                    selected_strat_version="$tag"
                    echo "Выбран тег: $tag"
                    break
                fi
                show_error "Неверный выбор. Попробуйте еще раз."
            done
            ;;
        *)
            show_error "Такого варианта нет"
            select_strategy_version_interactive
            ;;
    esac
}
