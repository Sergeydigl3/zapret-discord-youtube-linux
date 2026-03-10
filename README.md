<div align="center">

# 🎧 Zapret Discord YouTube Linux 📺

### Plug-And-Play адаптер для обхода замедления YouTube на Linux

На базе стратегий [Flowseal](https://github.com/Flowseal/zapret-discord-youtube) и [zapret](https://github.com/bol-van/zapret) от bol-van

**Проверено на:**
Ubuntu 24.04 • Debian 12 • Arch Linux • Gentoo Linux

[![Telegram Channel](https://img.shields.io/badge/Telegram-Канал-2CA5E0?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/+oOPnF-TKMAIxMjg6)
[![Telegram Chat](https://img.shields.io/badge/Telegram-Чат-2CA5E0?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/+mPohxYQQdZoyMjRi)

[![Boosty](https://img.shields.io/badge/Boosty-Сказать_спасибо-FF6154?style=for-the-badge&logo=data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KPHBhdGggZD0iTTEyIDI0QzE4LjYyNzQgMjQgMjQgMTguNjI3NCAyNCAxMkMyNCA1LjM3MjU4IDE4LjYyNzQgMCAxMiAwQzUuMzcyNTggMCAwIDUuMzcyNTggMCAxMkMwIDE4LjYyNzQgNS4zNzI1OCAyNCAxMiAyNFoiIGZpbGw9IndoaXRlIi8+Cjwvc3ZnPgo=&logoColor=white)](https://boosty.to/sergeydigl3/about)

[![GitHub stars](https://img.shields.io/github/stars/Sergeydigl3/zapret-discord-youtube-linux?style=social)](https://github.com/Sergeydigl3/zapret-discord-youtube-linux/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/Sergeydigl3/zapret-discord-youtube-linux?style=social)](https://github.com/Sergeydigl3/zapret-discord-youtube-linux/network/members)

</div>

---

<div align="center">

[Быстрый старт](#быстрый-старт) • [Использование](#использование) • [Автозагрузка](#автозагрузка) • [Поддержка](#поддержка-и-помощь)


</div>

## Быстрый старт

```bash
git clone https://github.com/Sergeydigl3/zapret-discord-youtube-linux.git
cd zapret-discord-youtube-linux

./service.sh download-deps --default
./service.sh
```

Скрипт интерактивно предложит выбрать действие: запуск, управление сервисом или настройку конфигурации.

> 💡 **Работа без пароля:** `./service.sh setup-permissions` — настроит NOPASSWD для nft/nfqws

> 💡 Что-то не работает? Сначала прочитайте раздел [Поддержка и помощь](#поддержка-и-помощь)

---

**Требования:**
- Работает только с **nftables**
- Поддерживаемые архитектуры: **x86_64, ARM, MIPS, и др** (автоматическое определение)

---

## О версиях

Адаптер по умолчанию использует:
- **nfqws**: v72.9 (рекомендованная версия, прописана в `src/lib/constants.sh` как `ZAPRET_RECOMMENDED_VERSION`)
- **Стратегии**: [коммит cb9aed09449e1c51a9108c7989717c7c98a14301](https://github.com/Flowseal/zapret-discord-youtube/commit/cb9aed09449e1c51a9108c7989717c7c98a14301) (прописан в `src/lib/constants.sh` как `MAIN_REPO_REV`)

Вы можете изменить версии:
- Интерактивно: `./service.sh download-deps` (выбор из доступных версий)
- Напрямую: `./service.sh download-deps -z v72.9 -s main`
- В коде: отредактируйте константы в `src/lib/constants.sh`

Если текущая версия не работает, попробуйте [стабильные релизы](https://github.com/Sergeydigl3/zapret-discord-youtube-linux/releases).

**Сторонние проекты:**
- [Версия от Snowy-Fluffy](https://github.com/Snowy-Fluffy/zapret.installer)

---

# Использование

## Интерактивный режим

```bash
./service.sh
```

Меню предлагает:
1. **Запустить** — интерактивный выбор интерфейса, gamefilter и стратегии, запуск в текущем терминале
2. **Управление сервисом** — установка/удаление/перезапуск системного сервиса
3. **Изменить конфигурацию** — редактирование `conf.env`

## Конфигурация (conf.env)

Создайте файл `conf.env`:

```bash
strategy=general.bat
interface=enp0s3
gamefilter=true
router_mode=false
```

## Router mode

Router mode позволяет использовать zapret **на всех устройствах в вашей локальной сети** — телефонах, планшетах, Smart TV и др. — без установки чего-либо на эти устройства. Достаточно настроить шлюз по умолчанию на них (или в DHCP на роутере) на адрес Linux-машины с запущенным zapret.

Пример: 
1. На телефоне смотрим текущие настройки. IP, Маска, Шлюз (Gateway) (адрес вашего роутера), dns server.
2. Переключаем с DHCP, на статический адрес - И выставляем IP который и был, маска такая же. Вместо шлюза указываем локальный ip адрес компьютера/сервера где запущен запрет. В качестве dns сервера указываем адрес роутера.

Идеально для установки на одноплатный компьютер, старый ноутбук, lxc контейнер в proxmox и тд...

> **Примечание:** При включении router mode автоматически активируется `net.ipv4.ip_forward` и создаётся NAT (masquerade). Настройка сохраняется в `/etc/sysctl.d/99-zapret_discord_youtube.conf` и применяется при каждом старте. При остановке — автоматически убирается.

---

## Управление через CLI

### Основные команды

```bash
./service.sh --help  # показать справку по командам
```

### Управление зависимостями

```bash
# Скачать nfqws и стратегии (интерактивный выбор версий)
./service.sh download-deps

# Скачать рекомендованные версии (неинтерактивно)
./service.sh download-deps --default

# Скачать конкретные версии
./service.sh download-deps -z v72.9 -s main

# Показать доступные стратегии
./service.sh strategy list
```

### Запуск zapret

```bash
# Интерактивный режим (запрос параметров)
./service.sh run

# Загрузка из конфигурационного файла
./service.sh run --config conf.env

# Прямые параметры
./service.sh run -s general.bat -i enp0s3
./service.sh run -s general.bat -i enp0s3 -g  # с gamefilter
./service.sh run -s general.bat -i enp0s3 -r  # в режиме роутера
```

### Управление системным сервисом

```bash
# Интерактивное меню управления сервисом
./service.sh service

# Установить и запустить сервис
./service.sh service install

# Показать статус
./service.sh service status

# Запустить/остановить/перезапустить
./service.sh service start
./service.sh service stop
./service.sh service restart

# Удалить сервис
./service.sh service remove
```

### Управление конфигурацией

```bash
# Показать текущую конфигурацию
./service.sh config show

# Интерактивное редактирование
./service.sh config edit

# Установить конфигурацию напрямую
./service.sh config set general.bat
./service.sh config set general.bat enp0s3 -g  # с gamefilter
./service.sh config set general.bat enp0s3 -r  # в режиме роутера
./service.sh config set discord -n             # без перезапуска сервиса
```

### Создание ярлыка в меню приложений

```bash
# Создать ярлык в меню приложений (для GUI запуска)
./service.sh desktop install

# Удалить ярлык из меню приложений
./service.sh desktop remove
```

После установки ярлыка вы сможете запустить zapret из меню приложений вашей системы (категория "Сеть" или "Система").

### Утилиты

```bash
# Остановить nfqws и очистить nftables
./service.sh kill
```

---

## Автоматический подбор стратегий

```bash
./auto_tune_youtube.sh
```

Скрипт автоматически:
1. Перебирает стратегии из `/custom-strategies` и `/zapret-latest` (начинающиеся на `general`)
2. Тестирует доступ к YouTube
3. Сохраняет результаты в `auto_tune_youtube_results.txt`
4. Предлагает запустить или сохранить рабочую стратегию в `conf.env`

> Функционал экспериментальный, достоверность не гарантирована

---

## Автозагрузка (системный сервис)

```bash
# Через CLI
./service.sh service install

# Или через интерактивное меню
./service.sh
# -> выбрать "2. Управление сервисом" -> "1. Установить и запустить сервис"
```

Скрипт:
- Проверяет `conf.env` (если пустой — запросит параметры интерактивно)
- Создаёт сервис для автозапуска (поддерживает systemd, OpenRC, runit, s6, dinit)
- Использует значения из `conf.env`

<details>
<summary>Для systemd систем</summary>

Просмотреть статус сервиса можно командой:

```bash
systemctl status zapret_discord_youtube.service
```

Посмотреть логи сервиса:

```bash
journalctl -u zapret_discord_youtube.service
```

</details>

<details>
<summary>Для OpenRC систем</summary>

Просмотреть статус сервиса можно командой:

```bash
rc-service zapret_discord_youtube status
```

Посмотреть логи сервиса:

```bash
rc-service zapret_discord_youtube logs
```

</details>

<details>
<summary>Для runit систем</summary>

Просмотреть статус сервиса можно командой:

```bash
sv status zapret_discord_youtube
```

Посмотреть логи сервиса:

```bash
tail -f /var/log/zapret_discord_youtube/current
```

</details>

<details>
<summary>Для s6 систем</summary>

Просмотреть статус сервиса можно командой:

```bash
s6-svstat /var/service/zapret_discord_youtube
```

Посмотреть логи сервиса:

```bash
tail -f /var/log/zapret_discord_youtube/current
```

</details>

<details>
<summary>Для dinit систем</summary>

Просмотреть статус сервиса можно командой:

```bash
dinitctl status zapret_discord_youtube
```

Посмотреть логи сервиса:

```bash
dinitctl log zapret_discord_youtube
```

</details>

---

## Поддержка и помощь

> [!IMPORTANT]
> Это АДАПТЕР! Не гарантирует, что стратегии разблокируют всё.

### Если ничего не работает

**Прежде чем создавать Issue или Discussion:**

1. Посмотрите [Issues в репозитории со стратегиями](https://github.com/Flowseal/zapret-discord-youtube/issues) — возможно, проблема уже обсуждается там
2. Попробуйте другие стратегии или воспользуйтесь [автоматическим подбором](#автоматический-подбор-стратегий)
3. Проверьте [Discussions](https://github.com/Flowseal/zapret-discord-youtube/discussions) — там обсуждают рабочие решения

### Когда создавать Issue/Discussion у меня

**Когда писать в [Issues](https://github.com/Sergeydigl3/zapret-discord-youtube-linux/issues):**
- Ошибки в работе **скрипта адаптера**
- Вопросы по работе **скрипта адаптера**
- Предложение добавить стратегию в custom-strategies

**Когда писать в [Discussions](https://github.com/Sergeydigl3/zapret-discord-youtube-linux/discussions):**
- Не работает YouTube или другой сайт (после проверки репозитория Flowseal)
- Поиск рабочих стратегий
- Обмен опытом

**Pull Request приветствуются** (например, поддержка iptables)

---

## Контрибьюторы

<div align="center">

**Спасибо всем, кто улучшает проект!** 🎉

<a href="https://github.com/Sergeydigl3/zapret-discord-youtube-linux/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=Sergeydigl3/zapret-discord-youtube-linux" alt="Contributors" />
</a>

Хотите видеть здесь свое имя? Сделайте [Pull Request](https://github.com/Sergeydigl3/zapret-discord-youtube-linux/pulls)!

</div>

---

<div align="center">

[![Star History Chart](https://api.star-history.com/svg?repos=Sergeydigl3/zapret-discord-youtube-linux&type=Date)](https://star-history.com/#Sergeydigl3/zapret-discord-youtube-linux&Date)

</div>
