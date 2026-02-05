# Проверка инита для запуска соответствующего скрипта
INIT=$(ps -p 1 -o comm=)

# Путь к запрету и его скриптам
HOME_DIR_PATH="$(dirname "$0")" 
DINIT_SERVICE_PATH="$(dirname "$0")/inits/dinit.sh"
SYSTEMD_SERVICE_PATH="$(dirname "$0")/inits/systemd.sh"

if [ ! -z $(echo "$INIT" | grep "systemd") ]; then
	$SYSTEMD_SERVICE_PATH
elif [ ! -z $(echo "$INIT" | grep "dinit") ]; then
	$DINIT_SERVICE_PATH
fi

