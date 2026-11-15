# W11 Pro Debloat - instalador de una linea
#   irm https://raw.githubusercontent.com/hombrelobo2/w11prodebloat/main/install.ps1 | iex
# Descarga la ultima version del script a C:\ProgramData\W11Debloat y la abre como administrador.
$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$dir = Join-Path $env:ProgramData 'W11Debloat'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$dst = Join-Path $dir 'w11-debloat.ps1'
$url = 'https://raw.githubusercontent.com/hombrelobo2/w11prodebloat/main/w11-debloat.ps1?t=' + [DateTime]::UtcNow.Ticks
Write-Host 'Descargando W11 Pro Debloat...' -ForegroundColor Cyan
(New-Object System.Net.WebClient).DownloadFile($url, $dst)
Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$dst`" -NoUpdate"
