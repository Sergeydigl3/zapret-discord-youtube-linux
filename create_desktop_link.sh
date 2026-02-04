#!/bin/bash

# 1. Сбор данных с проверкой на непустоту
echo -n "GameFilter по умолчанию [y/N]? "
read game_mode_yn
game_mode_yn=${game_mode_yn:-n} # Умолчание: n

# Цикл для обязательного ввода стратегии
while [[ -z "$default_mode" ]]; do
    echo -n "Введите стратегию по умолчанию (обязательно): "
    read default_mode
    [[ -z "$default_mode" ]] && echo "Ошибка: поле не может быть пустым."
done

# Цикл для обязательного ввода интерфейса
while [[ -z "$default_interface" ]]; do
    echo -n "Введите интерфейс по умолчанию (обязательно): "
    read default_interface
    [[ -z "$default_interface" ]] && echo "Ошибка: поле не может быть пустым."
done

SCRIPT_DIR=$(pwd)
MAIN_SCRIPT_PATH="$SCRIPT_DIR/main_script.sh"

# 2. Создание .desktop файла
cat <<EOF > zapret.desktop
[Desktop Entry]
Name=Zapret Auto
Comment=Run script with auto-input
Exec=bash -c 'printf "$game_mode_yn\n$default_mode\n$default_interface\n" | sudo "$MAIN_SCRIPT_PATH"; exec bash'
Icon=utilities-terminal
Terminal=true
Type=Application
Categories=Network;
EOF

chmod +x zapret.desktop
echo -e "\n[✔] Ярлык создан: $SCRIPT_DIR/zapret.desktop"

# 3. Настройка sudoers.d
echo -e "\nСоздать файл в /etc/sudoers.d/? (позволит запускать через ярлык без ввода пароля) [y/N]"
read whether_add_to_sudoers
whether_add_to_sudoers=${whether_add_to_sudoers:-n} # Умолчание: n

if [[ "$whether_add_to_sudoers" =~ ^[Yy]$ ]]; then
    # Определяем имя пользователя (logname надежнее внутри sudo)
    USER_NAME=$(logname 2>/dev/null || echo $USER)
    SUDOERS_CONF="/etc/sudoers.d/zapret-shortcut"

    echo "Настройка sudoers для пользователя $USER_NAME..."

    # Создаем правило NOPASSWD
    echo "$USER_NAME ALL=(root) NOPASSWD: $MAIN_SCRIPT_PATH" | sudo tee "$SUDOERS_CONF" > /dev/null

    # Права 0440 обязательно для работы sudoers.d
    sudo chmod 0440 "$SUDOERS_CONF"

    echo "Конфигурация sudoers.d обновлена."
else
    echo "Настройка sudoers.d пропущена. При запуске потребуется ввод пароля."
fi
