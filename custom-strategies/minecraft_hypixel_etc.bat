@echo off
chcp 65001 > nul
:: 65001 - UTF-8

cd /d "%~dp0"
call service.bat status_zapret
call service.bat check_updates
call service.bat load_game_filter
echo:

set "BIN=%~dp0bin\"
set "LISTS=%~dp0lists\"
cd /d %BIN%


start "zapret: %~n0" /min "%BIN%winws.exe" ^
--wf-tcp=80,443,2053,2083,2087,2096,8443,25565 ^
--wf-udp=443,19294-19344,50000-50100,25565 ^

--filter-tcp=25565 --ipset-exclude="%LISTS%ipset-exclude.txt" --dpi-desync-any-protocol=1 --dpi-desync-cutoff=n5 --dpi-desync=multisplit --dpi-desync-split-seqovl=582 --dpi-desync-split-pos=1 --dpi-desync-split-seqovl-pattern="%BIN%tls_clienthello_4pda_to.bin" --new ^
