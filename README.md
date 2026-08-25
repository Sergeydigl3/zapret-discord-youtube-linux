# Zapret Discord YouTube Linux

Plug-and-play адаптер стратегий [Flowseal/zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube) для Linux (nfqws).

Форк [Sergeydigl3/zapret-discord-youtube-linux](https://github.com/Sergeydigl3/zapret-discord-youtube-linux) с пином:
- **nfqws**: v72.13 (`ZAPRET_RECOMMENDED_VERSION`)
- **Стратегии**: [Flowseal 1.10.2](https://github.com/Flowseal/zapret-discord-youtube/releases/tag/1.10.2) (`MAIN_REPO_REV`)

## Быстрый старт

```bash
git clone https://github.com/mandyfan10-stack/zapret-discord-youtube-linux-1.git
cd zapret-discord-youtube-linux-1

./service.sh download-deps --default
./service.sh
```

## Команды

```bash
./service.sh --help
./service.sh download-deps
./service.sh download-deps --default
./service.sh download-deps -z v72.13 -s 1.10.2
./service.sh strategy list
./service.sh run
./service.sh run --config conf.env
./service.sh run -s general.bat -i enp0s3
./service.sh service install
./service.sh service status
./service.sh config set general.bat
./service.sh setup-permissions
./service.sh kill
```
