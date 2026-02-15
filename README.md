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
git clone https://github.com/Sergeydigl3/zapret-discord-youtube-linux.git && cd zapret-discord-youtube-linux
sudo bash main_script.sh
```

Скрипт интерактивно предложит выбрать стратегию и сетевой интерфейс.

> 💡 Что-то не работает? Сначала прочитайте раздел [Поддержка и помощь](#поддержка-и-помощь)

---

**Требования:**
- Работает только с **nftables**
- Поддерживается архитектура **x86_64** (для других архитектур замените бинарник nfqws на нужный)

---

## О версиях

Адаптер использует стратегии с [этого коммита](https://github.com/Flowseal/zapret-discord-youtube/commit/7952e58ee8b068b731d55d2ef8f491fd621d6ff0) (прописано в `main_script.sh` как `MAIN_REPO_REV`). Можно изменить на другой коммит при необходимости.

Если текущая версия не работает, попробуйте [стабильные релизы](https://github.com/Sergeydigl3/zapret-discord-youtube-linux/releases).

**Сторонние проекты:**
- [Версия от Snowy-Fluffy](https://github.com/Snowy-Fluffy/zapret.installer)

> Обновляю скрипт редко, для поддержания работоспособности относительно версии для Win.

---

# Использование

## Интерактивный режим

Скрипт автоматически:
- Подкачает стратегии из репозитория
- Предложит выбрать стратегию из bat-файлов (`general.bat`, `general_mgts2.bat`, `general_alt5.bat`)
- Попросит выбрать сетевой интерфейс

Список интерфейсов:
```bash
ls /sys/class/net
```

## Неинтерактивный режим (conf.env)

Создайте файл `conf.env`:

```bash
strategy=general.bat
interface=enp0s3
gamefilter=true
```

Запуск:
```bash
sudo bash main_script.sh -nointeractive
```

Отладка: используйте флаг `-debug`

## Управление через CLI

```bash
bash ./service.sh --help  # список команд

# Примеры:
bash ./service.sh general.bat enp0s3
bash ./service.sh --gamefilter alt11
```

---

## Автоматический подбор стратегий

```bash
sudo bash auto_tune_youtube.sh
```

Скрипт автоматически:
1. Перебирает стратегии из `/custom-strategies` и `/zapret-latest` (начинающиеся на `general`)
2. Тестирует доступ к YouTube
3. Сохраняет результаты в `auto_tune_youtube_results.txt`
4. Предлагает запустить или сохранить рабочую стратегию в `conf.env`

> Функционал экспериментальный, достоверность не гарантирована

---

## Автозагрузка

```bash
sudo bash service.sh
```

Скрипт:
- Проверяет `conf.env` (если пустой — запросит параметры интерактивно)
- Создаёт сервис для автозапуска
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
