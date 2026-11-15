@echo off
:: W11 Pro Debloat - lanzador
:: Si w11-debloat.ps1 esta junto a este .bat, lo usa (y el propio script se autoactualiza).
:: Si no esta, descarga la ultima version desde GitHub. Este .bat puede ir solo en un USB.
setlocal
set "SCRIPT=%~dp0w11-debloat.ps1"
set "URL=https://raw.githubusercontent.com/hombrelobo2/w11prodebloat/main/w11-debloat.ps1"

if exist "%SCRIPT%" goto run

echo Descargando la ultima version desde GitHub...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; (New-Object Net.WebClient).DownloadFile('%URL%','%SCRIPT%')"
if exist "%SCRIPT%" goto run

:: Carpeta sin permiso de escritura: usar ProgramData
set "SCRIPT=%ProgramData%\W11Debloat\w11-debloat.ps1"
if not exist "%ProgramData%\W11Debloat" mkdir "%ProgramData%\W11Debloat"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; (New-Object Net.WebClient).DownloadFile('%URL%','%SCRIPT%')"
if not exist "%SCRIPT%" (
    echo No se pudo descargar el script. Comprueba la conexion a Internet.
    pause
    exit /b 1
)

:run
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
