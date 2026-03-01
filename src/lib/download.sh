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

# Скачивание релиза zapret
download_zapret_release() {
    local tag="$1"
    local archive="zapret-${tag}.tar.gz"
    local url="https://github.com/${ZAPRET_REPO}/releases/download/${tag}/${archive}"
    local tmp="/tmp/${archive}"

    log "Скачивание zapret: $url" >&2
    curl -fL "$url" -o "$tmp" || handle_error "Ошибка при скачивании zapret"
    echo "$tmp"
}

# Извлечение бинарника nfqws из архива
extract_nfqws_binary() {
    local archive="$1"
    local platform_dir="$2"
    local out_dir="$3"
    local binary_name="nfqws"
    local tmpdir
    tmpdir=$(mktemp -d)

    log "Извлечение архива zapret..." >&2
    tar -xzf "$archive" -C "$tmpdir" || handle_error "Ошибка при извлечении архива"

    local bin_path
    bin_path=$(find "$tmpdir" -type f -path "*binaries/${platform_dir}/${binary_name}" | head -n1 || true)

    [[ -z "$bin_path" ]] && handle_error "Бинарник ${binary_name} не найден для платформы ${platform_dir}"

    cp "$bin_path" "${out_dir}/${binary_name}"
    chmod +x "${out_dir}/${binary_name}"

    log "Бинарник сохранён: ${out_dir}/${binary_name}" >&2
    rm -rf "$tmpdir" "$archive"
}

# Главная функция скачивания nfqws
# Требует: BASE_DIR или NFQWS_PATH
download_nfqws() {
    local version="${1:-latest}"
    local out_dir="${BASE_DIR:-$(dirname "$NFQWS_PATH")}"

    log "Скачивание nfqws (версия: $version)..." >&2

    local platform tag archive

    platform=$(detect_platform_dir)
    log "Определена платформа: $platform" >&2

    tag=$(resolve_zapret_version "$version")
    log "Используется версия релиза: $tag" >&2

    archive=$(download_zapret_release "$tag")
    extract_nfqws_binary "$archive" "$platform" "$out_dir"

    # Проверяем что файл создан
    if [[ ! -f "$out_dir/nfqws" ]]; then
        handle_error "Бинарник nfqws не был создан"
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
                echo -e "\nВерсия не может быть пустой!\n"
                sleep 0.7
                select_zapret_version_interactive
                return 0
            fi
            ;;
        4)
            echo "Загрузка списка версий..."
            local tags
            tags=$(get_git_tags "https://github.com/${ZAPRET_REPO}")

            if [[ -z "$tags" ]]; then
                echo -e "\nНе удалось получить теги\n"
                sleep 0.7
                select_zapret_version_interactive
                return 0
            fi

            # Преобразуем в массив
            local tag_array=()
            while IFS= read -r line; do
                tag_array+=("$line")
            done <<< "$tags"

            if [[ ${#tag_array[@]} -eq 0 ]]; then
                echo -e "\nТеги не найдены\n"
                sleep 0.7
                select_zapret_version_interactive
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
                echo "Неверный выбор. Попробуйте еще раз."
            done
            ;;
        5)
            return 0
            ;;
        *)  
            echo -e "\nТакого варианта нет\n"
            sleep 0.7
            select_zapret_version_interactive
            return 0
            ;;
    esac
}

# Интерактивный выбор версии стратегий
# Записывает результат в переменную $selected_strat_version
select_strategy_version_interactive() {
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
                echo -e "\nВерсия не может быть пустой!\n"
                sleep 0.7
                select_strategy_version_interactive
                return 0
            fi
            ;;
            
        3)
            echo "Загрузка списка тегов..."
            local tags
            tags=$(get_git_tags "$REPO_URL")

            if [[ -z "$tags" ]]; then
                echo -e "\nНе удалось получить теги\n"
                sleep 0.7
                select_strategy_version_interactive
                return 0
            fi

            # Преобразуем в массив
            local tag_array=()
            while IFS= read -r line; do
                tag_array+=("$line")
            done <<< "$tags"

            if [[ ${#tag_array[@]} -eq 0 ]]; then
                echo -e "\nТеги не найдены\n"
                sleep 0.7
                select_strategy_version_interactive
                return 0
            fi

            echo ""
            echo "Доступные теги (от новых к старым):"
            select tag in "${tag_array[@]}"; do
                if [[ -n "$tag" ]]; then
                    selected_strat_version="$tag"
                    echo "Выбран тег: $tag"
                    break
                fi
                echo "Неверный выбор. Попробуйте еще раз."
            done
            ;;
        *)
            echo -e "\nТакого варианта нет\n"
            sleep 0.7
            select_strategy_version_interactive
            return 0
            ;;
    esac
}
