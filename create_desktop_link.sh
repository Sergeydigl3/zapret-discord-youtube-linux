#!/bin/bash

source ./service.sh

SCRIPT_DIR="$(pwd)"
CONF_FILE="$SCRIPT_DIR/conf.env"
MAIN_SCRIPT_PATH="$SCRIPT_DIR/main_script.sh"

if [ ! -f "$CONF_FILE" ]; then
    create_conf_file
else
    read -p "Найден файл конфигурации, необходимо ли его редактирование? [Y/n]: " whether_edit_conf

    if [[ ${whether_edit_conf:-Y} =~ ^[Yy]$ ]]; then
        edit_conf_file
    fi
fi

# 2. Создание .desktop файла
cat <<EOF > zapret.desktop
[Desktop Entry]
Name=Zapret Auto
Comment=Run script with auto-input
Exec=bash -c 'sudo "$MAIN_SCRIPT_PATH" -nointeractive; exec bash'
Icon=utilities-terminal
Terminal=true
Type=Application
Categories=Network;
EOF

chmod +x zapret.desktop
echo -e "\n[✔] Ярлык создан: $SCRIPT_DIR/zapret.desktop"

# 3. Настройка sudoers.d
echo -e "\nСоздать файл в /etc/sudoers.d/ для запуска программы из ярлыка без ввода пароля (потенциально небезопасно)? [y/N]:"
read whether_add_to_sudoers
whether_add_to_sudoers=${whether_add_to_sudoers:-n} # Умолчание: n

if [[ "$whether_add_to_sudoers" =~ ^[Yy]$ ]]; then
    # Определяем имя пользователя (logname для исключения ошибок при работе от root'а)
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
