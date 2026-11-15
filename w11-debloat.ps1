<#
=====================================================================
  W11 Debloat + Instalador de software
  - Se actualiza solo desde $UpdateUrl (GitHub raw, Gist, etc.)
  - Debloat por categorías (apps, telemetría, IA, anuncios, OneDrive...)
  - Cuenta local: bloquea cuentas Microsoft, crea admin local y genera
    autounattend.xml para instalar W11 sin cuenta Microsoft
  - Instalación automatizada de programas con winget
  - Puede quedarse instalado y reaplicarse solo tras cada actualización
    de Windows (las feature updates suelen reinstalar el bloat)

  Uso:
    Doble clic en Ejecutar.bat   (o)
    irm https://raw.githubusercontent.com/hombrelobo2/w11prodebloat/main/install.ps1 | iex   (o)
    powershell -ExecutionPolicy Bypass -File .\w11-debloat.ps1
    Parámetros: -Auto (aplica el perfil guardado sin preguntar)
                -NoUpdate (no busca actualizaciones del script)

  Repositorio: https://github.com/hombrelobo2/w11prodebloat
  Cada vez que publiques una versión nueva, sube $ScriptVersion: todos
  los equipos se actualizarán solos en el siguiente arranque.
=====================================================================
#>
[CmdletBinding()]
param(
    [switch]$Auto,
    [switch]$NoUpdate
)

$ScriptVersion = '1.0.0'
$UpdateUrl     = 'https://raw.githubusercontent.com/hombrelobo2/w11prodebloat/main/w11-debloat.ps1'
$InstallerUrl  = $UpdateUrl -replace 'w11-debloat\.ps1$', 'install.ps1'

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
$Root       = Join-Path $env:ProgramData 'W11Debloat'
$ConfigFile = Join-Path $Root 'config.json'
$InstalledScript = Join-Path $Root 'w11-debloat.ps1'
$TaskName   = 'W11Debloat-Reaplicar'
$UpdateConfigured = ($UpdateUrl -notmatch 'TU_USUARIO')

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
if (-not (Test-Path $Root)) { New-Item -ItemType Directory -Path $Root -Force | Out-Null }

# ------------------------------------------------------------------
#  Utilidades de salida
# ------------------------------------------------------------------
function Write-Info($m) { Write-Host "  [*] $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "  [+] $m" -ForegroundColor Green }
function Write-Warn2($m){ Write-Host "  [!] $m" -ForegroundColor Yellow }
function Write-Err($m)  { Write-Host "  [x] $m" -ForegroundColor Red }
function Pause-Key      { if (-not $Auto) { Write-Host ''; Read-Host '  Pulsa Enter para continuar' | Out-Null } }

function Save-Utf8Bom([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($true)))
}

function Get-RemoteScript {
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('Cache-Control', 'no-cache')
    $bytes = $wc.DownloadData($UpdateUrl + '?t=' + [DateTime]::UtcNow.Ticks)
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    return $text
}

function Get-ArgString {
    $a = @()
    if ($Auto)     { $a += '-Auto' }
    if ($NoUpdate) { $a += '-NoUpdate' }
    return ($a -join ' ')
}

# ------------------------------------------------------------------
#  Windows PowerShell 5.1 obligatorio (el módulo Appx falla en PS7)
# ------------------------------------------------------------------
if ($PSVersionTable.PSEdition -eq 'Core' -and $PSCommandPath) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $(Get-ArgString)"
    exit
}

# ------------------------------------------------------------------
#  Si se ejecuta vía "irm URL | iex" no hay archivo: lo guardamos
# ------------------------------------------------------------------
if (-not $PSCommandPath) {
    if ($UpdateConfigured) {
        try {
            Save-Utf8Bom $InstalledScript (Get-RemoteScript)
            Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$InstalledScript`" -NoUpdate $(Get-ArgString)"
        } catch { Write-Err "No se pudo descargar el script: $_" }
    } else {
        Write-Err 'Ejecuta el script desde un archivo .ps1 (o configura $UpdateUrl).'
    }
    return
}

# ------------------------------------------------------------------
#  Elevación a administrador
# ------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $(Get-ArgString)"
    } catch { Write-Err 'Hace falta ejecutar como administrador.' ; Start-Sleep 3 }
    exit
}

# ------------------------------------------------------------------
#  Autoactualización
# ------------------------------------------------------------------
function Update-Self {
    if ($NoUpdate -or -not $UpdateConfigured) { return }
    Write-Info "Buscando actualizaciones del script (versión local $ScriptVersion)..."
    try {
        $remote = Get-RemoteScript
        if ($remote -notmatch "(?m)^\`$ScriptVersion\s*=\s*'([0-9\.]+)'") {
            Write-Warn2 'El archivo remoto no tiene versión válida; se ignora.' ; return
        }
        $remoteVer = [version]$Matches[1]
        if ($remoteVer -le [version]$ScriptVersion) { Write-Ok 'El script está al día.' ; return }

        # Comprobación de sintaxis antes de reemplazar
        $errs = $null
        [void][Management.Automation.Language.Parser]::ParseInput($remote, [ref]$null, [ref]$errs)
        if ($errs -and $errs.Count -gt 0) { Write-Warn2 'La versión remota tiene errores de sintaxis; no se actualiza.' ; return }

        Copy-Item -LiteralPath $PSCommandPath -Destination "$PSCommandPath.bak" -Force
        Save-Utf8Bom $PSCommandPath $remote
        # Mantener sincronizada la copia instalada para la tarea programada
        if ((Test-Path $InstalledScript) -and ($InstalledScript -ne $PSCommandPath)) { Save-Utf8Bom $InstalledScript $remote }

        Write-Ok "Actualizado a la versión $remoteVer. Reiniciando el script..."
        Start-Sleep 1
        $style = ''; if ($Auto) { $style = '-WindowStyle Hidden ' }
        Start-Process powershell.exe -ArgumentList "-NoProfile $style-ExecutionPolicy Bypass -File `"$PSCommandPath`" -NoUpdate $(Get-ArgString)"
        exit
    } catch {
        Write-Warn2 "No se pudo comprobar si hay actualizaciones ($($_.Exception.Message))."
    }
}

# ------------------------------------------------------------------
#  Registro: HKLM directo; HKCU se aplica también al perfil Default
#  (así los usuarios nuevos nacen ya limpios)
# ------------------------------------------------------------------
$DefaultHive = 'Registry::HKEY_USERS\W11D_Default'
$script:DefaultHiveLoaded = $false

function Mount-DefaultHive {
    $dat = Join-Path $env:SystemDrive 'Users\Default\NTUSER.DAT'
    if (Test-Path $dat) {
        & reg.exe load 'HKU\W11D_Default' $dat 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $script:DefaultHiveLoaded = $true }
    }
}
function Dismount-DefaultHive {
    if ($script:DefaultHiveLoaded) {
        [GC]::Collect() ; [GC]::WaitForPendingFinalizers() ; Start-Sleep -Milliseconds 500
        & reg.exe unload 'HKU\W11D_Default' 2>&1 | Out-Null
        $script:DefaultHiveLoaded = $false
    }
}

function Set-Reg {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    try {
        if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
    } catch { Write-Verbose "No se pudo escribir $Path\$Name : $_" }
}

# Ruta relativa a HKCU, p.ej. 'Software\Microsoft\...'
function Set-UserReg {
    param([string]$SubPath, [string]$Name, $Value, [string]$Type = 'DWord')
    Set-Reg -Path "HKCU:\$SubPath" -Name $Name -Value $Value -Type $Type
    if ($script:DefaultHiveLoaded) { Set-Reg -Path "$DefaultHive\$SubPath" -Name $Name -Value $Value -Type $Type }
}

function Disable-Tasks([string[]]$Tasks) {
    foreach ($t in $Tasks) {
        $folder = (Split-Path $t -Parent) + '\'
        $name   = Split-Path $t -Leaf
        Get-ScheduledTask -TaskPath $folder -TaskName $name -ErrorAction SilentlyContinue |
            Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
    }
}

function Disable-Services([string[]]$Names) {
    foreach ($s in $Names) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc) {
            Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
            Set-Service -Name $s -StartupType Disabled -ErrorAction SilentlyContinue
        }
    }
}

$script:ProvCache = $null
function Remove-Apps([string[]]$Patterns) {
    if (-not $script:ProvCache) { $script:ProvCache = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue) }
    foreach ($p in $Patterns) {
        $pkgs = @(Get-AppxPackage -AllUsers -Name $p -ErrorAction SilentlyContinue)
        foreach ($pkg in $pkgs) {
            try {
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                Write-Ok "Quitada: $($pkg.Name)"
            } catch {
                try { Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop ; Write-Ok "Quitada: $($pkg.Name)" }
                catch { Write-Verbose "No se pudo quitar $($pkg.Name)" }
            }
        }
        foreach ($prov in ($script:ProvCache | Where-Object { $_.DisplayName -like $p })) {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -AllUsers -ErrorAction Stop | Out-Null
                Write-Ok "Desaprovisionada (no volverá en usuarios nuevos): $($prov.DisplayName)"
            } catch { Write-Verbose "No se pudo desaprovisionar $($prov.DisplayName)" }
        }
    }
}

# ------------------------------------------------------------------
#  CATEGORÍAS DE DEBLOAT
# ------------------------------------------------------------------
$BloatApps = @(
    'Microsoft.BingNews','Microsoft.BingWeather','Microsoft.BingSearch','Microsoft.BingFinance','Microsoft.BingSports',
    'Microsoft.GetHelp','Microsoft.Getstarted','Microsoft.MicrosoftOfficeHub','Microsoft.Office.OneNote',
    'Microsoft.MicrosoftSolitaireCollection','Microsoft.People','Microsoft.PowerAutomateDesktop','Microsoft.Todos',
    'Microsoft.WindowsFeedbackHub','Microsoft.WindowsMaps','Microsoft.ZuneVideo','Microsoft.549981C3F5F10',
    'Microsoft.Windows.DevHome','MicrosoftTeams','MSTeams','Microsoft.OutlookForWindows','microsoft.windowscommunicationsapps',
    'Microsoft.YourPhone','MicrosoftWindows.CrossDevice','Microsoft.SkypeApp','Microsoft.MixedReality.Portal',
    'Microsoft.Microsoft3DViewer','Microsoft.3DBuilder','Microsoft.Messaging','Microsoft.OneConnect','Microsoft.Wallet',
    'Microsoft.MicrosoftJournal','Microsoft.Edge.GameAssist','Clipchamp.Clipchamp','MicrosoftCorporationII.MicrosoftFamily',
    'Microsoft.StartExperiencesApp','Microsoft.Windows.Photos.LegacyApp'
)
# Terceros que vienen "de regalo" (solo se quitan en ejecución manual, no en la
# reaplicación automática, para no borrar algo que hayas instalado tú después)
$ThirdPartyBloat = @(
    '*SpotifyAB.SpotifyMusic*','*Disney*','*TikTok*','*Instagram*','*Facebook*','*CandyCrush*','*king.com*',
    '*LinkedIn*','*Netflix*','*AmazonVideo*','*Amazon.com.Amazon*','*BytedancePte*','*Duolingo*','*PicsArt*',
    '*Twitter*','*McAfee*','*Norton*','*ExpressVPN*','*HiddenCity*','*MarchofEmpires*','*Royal Revolt*'
)

function Invoke-CatApps {
    Write-Info 'Quitando apps preinstaladas...'
    Remove-Apps $BloatApps
    if (-not $Auto) { Remove-Apps $ThirdPartyBloat }
}

function Invoke-CatTelemetry {
    Write-Info 'Desactivando telemetría y rastreo...'
    $dc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
    Set-Reg $dc 'AllowTelemetry' 0
    Set-Reg $dc 'MaxTelemetryAllowed' 0
    Set-Reg $dc 'DoNotShowFeedbackNotifications' 1
    Set-Reg $dc 'DisableOneSettingsDownloads' 1
    Set-Reg $dc 'LimitDiagnosticLogCollection' 1
    Set-Reg $dc 'LimitDumpCollection' 1
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1
    Set-UserReg 'Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
    # Historial de actividad
    $sys = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
    Set-Reg $sys 'EnableActivityFeed' 0
    Set-Reg $sys 'PublishUserActivities' 0
    Set-Reg $sys 'UploadUserActivities' 0
    # Experiencias personalizadas, comentarios, entrada de texto
    Set-UserReg 'Software\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1
    Set-UserReg 'Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
    Set-UserReg 'Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
    Set-UserReg 'Software\Microsoft\Siuf\Rules' 'PeriodInNanoSeconds' 0
    Set-UserReg 'Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1
    Set-UserReg 'Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1
    Set-UserReg 'Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0
    Set-UserReg 'Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0
    Set-UserReg 'Software\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack' 'ShowedToastAtLevel' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows' 'CEIPEnable' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'AITEnable' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableInventory' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\TabletPC' 'PreventHandwritingDataSharing' 1
    # Seguimiento de apps iniciadas
    Set-UserReg 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackProgs' 0

    Disable-Services @('DiagTrack','dmwappushservice')
    Disable-Tasks @(
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp',
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
        '\Microsoft\Windows\Application Experience\StartupAppTask',
        '\Microsoft\Windows\Application Experience\MareBackup',
        '\Microsoft\Windows\Autochk\Proxy',
        '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
        '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
        '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
        '\Microsoft\Windows\Feedback\Siuf\DmClient',
        '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
        '\Microsoft\Windows\Windows Error Reporting\QueueReporting'
    )
    Write-Ok 'Telemetría reducida al mínimo que permite tu edición de Windows.'
}

function Invoke-CatAI {
    Write-Info 'Desactivando IA (Copilot, Recall, Click to Do, IA en Paint/Bloc de notas/Edge)...'
    # Copilot
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    Set-UserReg 'Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    Set-UserReg 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCopilotButton' 0
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot' 'IsCopilotAvailable' 0
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot' 'CopilotDisabledReason' 'IsEnabledForGeographicRegionFailed' 'String'
    Set-UserReg 'Software\Microsoft\Windows\Shell\Copilot\BingChat' 'IsUserEligible' 0
    # Menú contextual "Preguntar a Copilot"
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked' '{CB3B0003-8088-4EDE-8769-8B354AB2FF8C}' '' 'String'
    Remove-Apps @('Microsoft.Copilot','Microsoft.Windows.Ai.Copilot.Provider','Microsoft.MicrosoftOfficeHub','Microsoft.Windows.AIX*')
    # Recall / Click to Do
    $ai = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'
    Set-Reg $ai 'DisableAIDataAnalysis' 1
    Set-Reg $ai 'AllowRecallEnablement' 0
    Set-Reg $ai 'TurnOffSavingSnapshots' 1
    Set-Reg $ai 'DisableClickToDo' 1
    Set-Reg $ai 'DisableSettingsAgent' 1
    Set-UserReg 'Software\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
    Set-UserReg 'Software\Policies\Microsoft\Windows\WindowsAI' 'TurnOffSavingSnapshots' 1
    Set-UserReg 'Software\Policies\Microsoft\Windows\WindowsAI' 'DisableClickToDo' 1
    try {
        $f = Get-WindowsOptionalFeature -Online -FeatureName 'Recall' -ErrorAction Stop
        if ($f.State -eq 'Enabled') { Disable-WindowsOptionalFeature -Online -FeatureName 'Recall' -NoRestart -ErrorAction Stop | Out-Null ; Write-Ok 'Recall desinstalado.' }
    } catch {}
    # Paint
    $paint = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'
    foreach ($n in 'DisableCocreator','DisableGenerativeFill','DisableImageCreator','DisableGenerativeErase','DisableRemoveBackground') { Set-Reg $paint $n 1 }
    # Bloc de notas
    Set-Reg 'HKLM:\SOFTWARE\Policies\WindowsNotepad' 'DisableAIFeatures' 1
    # Edge: barra lateral / Copilot
    $edge = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    Set-Reg $edge 'HubsSidebarEnabled' 0
    Set-Reg $edge 'CopilotCDPPageContext' 0
    Set-Reg $edge 'CopilotPageContext' 0
    Set-Reg $edge 'Microsoft365CopilotChatIconEnabled' 0
    Set-Reg $edge 'DiscoverPageContextEnabled' 0
    Set-Reg $edge 'ComposeInlineEnabled' 0
    Set-Reg $edge 'GenAILocalFoundationalModelSettings' 1
    Write-Ok 'IA desactivada.'
}

function Invoke-CatAds {
    Write-Info 'Quitando anuncios, sugerencias y Bing de la búsqueda...'
    $cdm = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    foreach ($n in 'ContentDeliveryAllowed','FeatureManagementEnabled','OemPreInstalledAppsEnabled','PreInstalledAppsEnabled',
                   'PreInstalledAppsEverEnabled','SilentInstalledAppsEnabled','SoftLandingEnabled','SystemPaneSuggestionsEnabled',
                   'RotatingLockScreenEnabled','RotatingLockScreenOverlayEnabled','SubscribedContentEnabled',
                   'SubscribedContent-310093Enabled','SubscribedContent-314563Enabled','SubscribedContent-338387Enabled',
                   'SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-338393Enabled',
                   'SubscribedContent-353694Enabled','SubscribedContent-353696Enabled','SubscribedContent-353698Enabled') {
        Set-UserReg $cdm $n 0
    }
    $cc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
    Set-Reg $cc 'DisableWindowsConsumerFeatures' 1
    Set-Reg $cc 'DisableConsumerAccountStateContent' 1
    Set-Reg $cc 'DisableSoftLanding' 1
    Set-Reg $cc 'DisableCloudOptimizedContent' 1
    Set-UserReg 'Software\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsSpotlightFeatures' 1
    Set-UserReg 'Software\Policies\Microsoft\Windows\CloudContent' 'DisableThirdPartySuggestions' 1
    # Recomendaciones del menú Inicio y notificaciones de cuenta
    $adv = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-UserReg $adv 'Start_IrisRecommendations' 0
    Set-UserReg $adv 'Start_AccountNotifications' 0
    Set-UserReg $adv 'ShowSyncProviderNotifications' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'HideRecommendedPersonalizedSites' 1
    # Bing / web en la búsqueda
    Set-UserReg 'Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
    Set-UserReg 'Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
    Set-UserReg 'Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 0
    $ws = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
    Set-Reg $ws 'AllowCortana' 0
    Set-Reg $ws 'DisableWebSearch' 1
    Set-Reg $ws 'ConnectedSearchUseWeb' 0
    Set-Reg $ws 'EnableDynamicContentInWSB' 0
    # "Terminemos de configurar el dispositivo" y similares
    Set-UserReg 'Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
    # Edge: compras, recomendaciones
    $edge = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    Set-Reg $edge 'EdgeShoppingAssistantEnabled' 0
    Set-Reg $edge 'ShowRecommendationsEnabled' 0
    Set-Reg $edge 'PersonalizationReportingEnabled' 0
    Set-Reg $edge 'HideFirstRunExperience' 1
    Write-Ok 'Anuncios y sugerencias desactivados.'
}

function Invoke-CatTaskbar {
    Write-Info 'Limpiando widgets y barra de tareas...'
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' 'EnableFeeds' 0
    $adv = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-UserReg $adv 'TaskbarMn' 0
    Set-UserReg $adv 'TaskbarDa' 0
    Set-UserReg 'Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 1
    Set-UserReg 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' 'TaskbarEndTask' 1
    Remove-Apps @('MicrosoftWindows.Client.WebExperience','Microsoft.WidgetsPlatformRuntime')
    Write-Ok 'Widgets y chat fuera; búsqueda como icono; "Finalizar tarea" en la barra.'
}

function Invoke-CatOneDrive {
    Write-Info 'Desinstalando OneDrive...'
    Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    foreach ($exe in "$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") {
        if (Test-Path $exe) { Start-Process $exe -ArgumentList '/uninstall' -Wait -ErrorAction SilentlyContinue }
    }
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        & winget uninstall --id Microsoft.OneDrive -e --silent --accept-source-agreements 2>&1 | Out-Null
    }
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1
    Set-UserReg 'Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' 'System.IsPinnedToNameSpaceTree' 0
    # Evita que se reinstale en usuarios nuevos
    if ($script:DefaultHiveLoaded) {
        Remove-ItemProperty -LiteralPath "$DefaultHive\Software\Microsoft\Windows\CurrentVersion\Run" -Name 'OneDriveSetup' -ErrorAction SilentlyContinue
    }
    Write-Ok 'OneDrive quitado (tus archivos en la nube siguen en onedrive.com).'
}

function Invoke-CatLocalAccount {
    Write-Info 'Configurando inicio de sesión solo local...'
    $sys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    # 1 = no se pueden añadir cuentas Microsoft (las existentes siguen funcionando)
    $cur = (Get-ItemProperty -LiteralPath $sys -Name 'NoConnectedUser' -ErrorAction SilentlyContinue).NoConnectedUser
    if ($cur -ne 3) { Set-Reg $sys 'NoConnectedUser' 1 }
    # Permite saltarse el requisito de red/cuenta si reinstalas o restableces
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'BypassNRO' 1
    # Quita los avisos para "iniciar sesión con tu cuenta Microsoft"
    Set-UserReg 'Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
    Set-UserReg 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_AccountNotifications' 0
    Set-UserReg 'Software\Microsoft\Windows\CurrentVersion\SystemSettings\AccountNotifications' 'EnableAccountNotifications' 0
    $src = Get-AccountType
    if ($src -eq 'MicrosoftAccount') {
        Write-Warn2 "Tu usuario actual ($env:USERNAME) es una cuenta Microsoft. Usa la opción 3 del menú para crear una cuenta local."
    } else {
        Write-Ok 'Ya usas una cuenta local. Se ha bloqueado añadir cuentas Microsoft.'
    }
}

function Invoke-CatExplorer {
    Write-Info 'Ajustes clásicos del Explorador...'
    $adv = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-UserReg $adv 'HideFileExt' 0          # mostrar extensiones
    Set-UserReg $adv 'LaunchTo' 1             # abrir en "Este equipo"
    Set-UserReg 'Software\Microsoft\Windows\CurrentVersion\Explorer' 'ShowRecent' 0
    Set-UserReg 'Software\Microsoft\Windows\CurrentVersion\Explorer' 'ShowFrequent' 0
    Set-UserReg 'Software\Microsoft\Windows\CurrentVersion\Explorer' 'ShowCloudFilesInQuickAccess' 0
    # Menú contextual clásico (clic derecho completo)
    Set-UserReg 'Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' '(default)' '' 'String'
    Write-Ok 'Extensiones visibles, menú contextual clásico, abre en Este equipo.'
}

function Invoke-CatTaskbarLeft {
    Write-Info 'Alineando la barra de tareas a la izquierda...'
    Set-UserReg 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAl' 0
    Write-Ok 'Barra a la izquierda.'
}

function Invoke-CatXbox {
    Write-Info 'Quitando apps de Xbox y Game DVR...'
    Remove-Apps @('Microsoft.GamingApp','Microsoft.XboxApp','Microsoft.XboxGamingOverlay','Microsoft.XboxGameOverlay','Microsoft.XboxSpeechToTextOverlay')
    Set-UserReg 'System\GameConfigStore' 'GameDVR_Enabled' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
    Write-Ok 'Xbox quitado (Xbox Identity Provider se mantiene para no romper juegos).'
}

$Categories = @(
    [pscustomobject]@{ Key='apps';      Name='Apps preinstaladas (Noticias, Tiempo, Teams, Clipchamp, Solitario, juegos de regalo...)'; Default=$true;  Run={ Invoke-CatApps } }
    [pscustomobject]@{ Key='telemetry'; Name='Telemetría, rastreo, historial de actividad, ID de publicidad';                           Default=$true;  Run={ Invoke-CatTelemetry } }
    [pscustomobject]@{ Key='ai';        Name='IA: Copilot, Recall, Click to Do, IA de Paint/Bloc de notas/Edge';                         Default=$true;  Run={ Invoke-CatAI } }
    [pscustomobject]@{ Key='ads';       Name='Anuncios, sugerencias, recomendaciones de Inicio, Bing en la búsqueda';                    Default=$true;  Run={ Invoke-CatAds } }
    [pscustomobject]@{ Key='taskbar';   Name='Widgets, chat y búsqueda compacta en la barra de tareas';                                  Default=$true;  Run={ Invoke-CatTaskbar } }
    [pscustomobject]@{ Key='onedrive';  Name='Desinstalar OneDrive';                                                                     Default=$true;  Run={ Invoke-CatOneDrive } }
    [pscustomobject]@{ Key='local';     Name='Solo cuenta local (bloquear cuentas Microsoft y sus avisos)';                              Default=$true;  Run={ Invoke-CatLocalAccount } }
    [pscustomobject]@{ Key='explorer';  Name='Explorador clásico (extensiones, clic derecho completo, Este equipo)';                      Default=$true;  Run={ Invoke-CatExplorer } }
    [pscustomobject]@{ Key='left';      Name='Barra de tareas alineada a la izquierda';                                                  Default=$false; Run={ Invoke-CatTaskbarLeft } }
    [pscustomobject]@{ Key='xbox';      Name='Apps de Xbox y Game DVR (déjalo si usas Game Pass)';                                       Default=$false; Run={ Invoke-CatXbox } }
)

# ------------------------------------------------------------------
#  Configuración guardada
# ------------------------------------------------------------------
function Get-Config {
    if (Test-Path $ConfigFile) {
        try { return (Get-Content $ConfigFile -Raw | ConvertFrom-Json) } catch {}
    }
    return [pscustomobject]@{ Categories = @($Categories | Where-Object Default | ForEach-Object Key) }
}
function Save-Config($keys) {
    [pscustomobject]@{ Categories = @($keys); Version = $ScriptVersion; Saved = (Get-Date).ToString('s') } |
        ConvertTo-Json | Set-Content -Path $ConfigFile -Encoding UTF8
}

function Get-AccountType {
    try { return [string](Get-LocalUser -Name $env:USERNAME -ErrorAction Stop).PrincipalSource } catch { return 'Desconocido' }
}

# ------------------------------------------------------------------
#  Punto de restauración
# ------------------------------------------------------------------
function New-RestorePoint {
    Write-Info 'Creando punto de restauración...'
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' 'SystemRestorePointCreationFrequency' 0
        Checkpoint-Computer -Description "W11Debloat $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Ok 'Punto de restauración creado.'
    } catch { Write-Warn2 "No se pudo crear el punto de restauración: $($_.Exception.Message)" }
}

# ------------------------------------------------------------------
#  Aplicar debloat
# ------------------------------------------------------------------
function Invoke-Debloat([string[]]$Keys, [switch]$Quiet) {
    Mount-DefaultHive
    try {
        foreach ($c in $Categories) {
            if ($Keys -contains $c.Key) {
                Write-Host ''
                try { & $c.Run } catch { Write-Err "Error en '$($c.Name)': $_" }
            }
        }
    } finally { Dismount-DefaultHive }
    if (-not $Quiet) {
        Write-Info 'Reiniciando el Explorador para aplicar cambios...'
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep 2
        if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
        Write-Host ''
        Write-Ok 'Debloat terminado. Algunos cambios necesitan reiniciar el PC.'
    }
}

function Show-DebloatMenu {
    $sel = @{}
    $cfg = Get-Config
    foreach ($c in $Categories) { $sel[$c.Key] = ($cfg.Categories -contains $c.Key) }
    while ($true) {
        Clear-Host
        Write-Host "`n  === DEBLOAT: elige categorías ===`n" -ForegroundColor Magenta
        $i = 1
        foreach ($c in $Categories) {
            $mark = ' '; if ($sel[$c.Key]) { $mark = 'X' }
            Write-Host ("  {0,2}. [{1}] {2}" -f $i, $mark, $c.Name)
            $i++
        }
        Write-Host "`n  Número = marcar/desmarcar   T = todas   N = ninguna"
        Write-Host '  A = APLICAR                  0 = volver'
        $r = (Read-Host "`n  Opción").Trim().ToUpper()
        switch -Regex ($r) {
            '^0$' { return }
            '^T$' { foreach ($c in $Categories) { $sel[$c.Key] = $true } }
            '^N$' { foreach ($c in $Categories) { $sel[$c.Key] = $false } }
            '^A$' {
                $keys = @($Categories | Where-Object { $sel[$_.Key] } | ForEach-Object Key)
                if ($keys.Count -eq 0) { Write-Warn2 'No hay nada marcado.' ; Pause-Key ; continue }
                Save-Config $keys
                New-RestorePoint
                Invoke-Debloat $keys
                Pause-Key
                return
            }
            '^\d+$' {
                $n = [int]$r
                if ($n -ge 1 -and $n -le $Categories.Count) { $k = $Categories[$n - 1].Key ; $sel[$k] = -not $sel[$k] }
            }
        }
    }
}

# ------------------------------------------------------------------
#  INSTALADOR DE SOFTWARE (winget)
# ------------------------------------------------------------------
$Software = @(
    # Cat,            Nombre,                    Id winget,                              Origen,   Básico
    @('Navegadores',  'Google Chrome',           'Google.Chrome',                        'winget', $true),
    @('Navegadores',  'Mozilla Firefox',         'Mozilla.Firefox.es-ES',                'winget', $false),
    @('Navegadores',  'Brave',                   'Brave.Brave',                          'winget', $false),
    @('Multimedia',   'VLC',                     'VideoLAN.VLC',                         'winget', $true),
    @('Multimedia',   'OBS Studio',              'OBSProject.OBSStudio',                 'winget', $false),
    @('Multimedia',   'Audacity',                'Audacity.Audacity',                    'winget', $false),
    @('Compresión',   'WinRAR',                  'RARLab.WinRAR',                        'winget', $true),
    @('Compresión',   '7-Zip',                   '7zip.7zip',                            'winget', $false),
    @('Juegos',       'Steam',                   'Valve.Steam',                          'winget', $true),
    @('Juegos',       'Epic Games Launcher',     'EpicGames.EpicGamesLauncher',          'winget', $false),
    @('Juegos',       'GOG Galaxy',              'GOG.Galaxy',                           'winget', $false),
    @('Juegos',       'Discord',                 'Discord.Discord',                      'winget', $false),
    @('Descargas',    'qBittorrent',             'qBittorrent.qBittorrent',              'winget', $true),
    @('Seguridad',    'Avast Free Antivirus',    'XPDNZJFNCR1B07',                       'msstore',$true),
    @('Seguridad',    'Malwarebytes',            'Malwarebytes.Malwarebytes',            'winget', $false),
    @('Seguridad',    'Bitwarden',               'Bitwarden.Bitwarden',                  'winget', $false),
    @('Utilidades',   'Notepad++',               'Notepad++.Notepad++',                  'winget', $false),
    @('Utilidades',   'PowerToys',               'Microsoft.PowerToys',                  'winget', $false),
    @('Utilidades',   'Everything (buscador)',   'voidtools.Everything',                 'winget', $false),
    @('Utilidades',   'ShareX (capturas)',       'ShareX.ShareX',                        'winget', $false),
    @('Utilidades',   'CPU-Z',                   'CPUID.CPU-Z',                          'winget', $false),
    @('Utilidades',   'HWiNFO',                  'REALiX.HWiNFO',                        'winget', $false),
    @('Utilidades',   'CrystalDiskInfo',         'CrystalDewWorld.CrystalDiskInfo',      'winget', $false),
    @('Comunicación', 'Telegram',                'Telegram.TelegramDesktop',             'winget', $false),
    @('Comunicación', 'WhatsApp',                '9NKSQGP7F2NH',                         'msstore',$false),
    @('Oficina',      'LibreOffice',             'TheDocumentFoundation.LibreOffice',    'winget', $false),
    @('Oficina',      'Adobe Acrobat Reader',    'Adobe.Acrobat.Reader.64-bit',          'winget', $false),
    @('Oficina',      'SumatraPDF',              'SumatraPDF.SumatraPDF',                'winget', $false),
    @('Runtimes',     'Visual C++ 2015-2022 x64','Microsoft.VCRedist.2015+.x64',         'winget', $true),
    @('Runtimes',     'Visual C++ 2015-2022 x86','Microsoft.VCRedist.2015+.x86',         'winget', $true),
    @('Runtimes',     '.NET Desktop Runtime 8',  'Microsoft.DotNet.DesktopRuntime.8',    'winget', $false),
    @('Runtimes',     'DirectX (End-User)',      'Microsoft.DirectX',                    'winget', $false),
    @('Desarrollo',   'Visual Studio Code',      'Microsoft.VisualStudioCode',           'winget', $false),
    @('Desarrollo',   'Git',                     'Git.Git',                              'winget', $false)
) | ForEach-Object { [pscustomobject]@{ Cat=$_[0]; Name=$_[1]; Id=$_[2]; Source=$_[3]; Basic=$_[4] } }

function Ensure-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return $true }
    Write-Info 'winget no está disponible todavía; intentando registrarlo...'
    try { Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction Stop } catch {}
    Start-Sleep 3
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User') + ";$env:LOCALAPPDATA\Microsoft\WindowsApps"
    if (Get-Command winget -ErrorAction SilentlyContinue) { return $true }
    Write-Info 'Descargando App Installer (winget) de Microsoft...'
    try {
        $tmp = Join-Path $env:TEMP 'AppInstaller.msixbundle'
        (New-Object System.Net.WebClient).DownloadFile('https://aka.ms/getwinget', $tmp)
        Add-AppxPackage -Path $tmp -ErrorAction Stop
        Start-Sleep 3
    } catch { Write-Err "No se pudo instalar winget: $($_.Exception.Message)" }
    if (Get-Command winget -ErrorAction SilentlyContinue) { return $true }
    Write-Err 'winget no disponible. Actualiza "Instalador de aplicaciones" desde Microsoft Store y vuelve a intentarlo.'
    return $false
}

function Install-Software($items) {
    if (-not (Ensure-Winget)) { return }
    & winget source update 2>&1 | Out-Null
    $ok = @(); $fail = @()
    foreach ($s in $items) {
        Write-Info "Instalando $($s.Name)..."
        & winget install --id $s.Id -e --source $s.Source --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
        $code = $LASTEXITCODE
        # 0 = OK; -1978335189 = ya instalado / sin actualizaciones
        if ($code -eq 0 -or $code -eq -1978335189 -or $code -eq -1978335135) { $ok += $s.Name ; Write-Ok "$($s.Name) listo." }
        else {
            # Reintento por nombre (por si cambia el Id en el repositorio)
            & winget install --name $s.Name --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
            if ($LASTEXITCODE -eq 0) { $ok += $s.Name ; Write-Ok "$($s.Name) listo." }
            else { $fail += $s.Name ; Write-Err "$($s.Name) falló (código $code)." }
        }
    }
    Write-Host ''
    if ($ok.Count)   { Write-Ok   ("Instalados: " + ($ok -join ', ')) }
    if ($fail.Count) { Write-Warn2 ("Fallaron: " + ($fail -join ', ') + "  -> prueba de nuevo o instala a mano.") }
}

function Parse-Selection([string]$text, [int]$max) {
    $out = New-Object System.Collections.Generic.List[int]
    foreach ($part in ($text -split '[,\s]+' | Where-Object { $_ })) {
        if ($part -match '^(\d+)-(\d+)$') { [int]$Matches[1]..[int]$Matches[2] | ForEach-Object { if ($_ -ge 1 -and $_ -le $max) { $out.Add($_) } } }
        elseif ($part -match '^\d+$') { $n=[int]$part ; if ($n -ge 1 -and $n -le $max) { $out.Add($n) } }
    }
    return ($out | Select-Object -Unique)
}

function Show-SoftwareMenu {
    Clear-Host
    Write-Host "`n  === INSTALAR SOFTWARE (winget) ===`n" -ForegroundColor Magenta
    $i = 1 ; $lastCat = ''
    foreach ($s in $Software) {
        if ($s.Cat -ne $lastCat) { Write-Host "`n  -- $($s.Cat) --" -ForegroundColor DarkCyan ; $lastCat = $s.Cat }
        $b = '' ; if ($s.Basic) { $b = ' *' }
        Write-Host ("  {0,2}. {1}{2}" -f $i, $s.Name, $b)
        $i++
    }
    Write-Host "`n  * = incluido en el pack básico"
    Write-Host '  Escribe números (ej: 1 4 7  o  1,3,5-9), B = pack básico, T = todo, 0 = volver'
    $r = (Read-Host "`n  Selección").Trim().ToUpper()
    if ($r -eq '0' -or $r -eq '') { return }
    if ($r -eq 'B') { $items = @($Software | Where-Object Basic) }
    elseif ($r -eq 'T') { $items = @($Software) }
    else { $items = @(Parse-Selection $r $Software.Count | ForEach-Object { $Software[$_ - 1] }) }
    if ($items.Count -eq 0) { Write-Warn2 'Nada seleccionado.' ; Pause-Key ; return }
    Write-Host "`n  Se instalará: $(($items | ForEach-Object Name) -join ', ')"
    if ((Read-Host '  ¿Continuar? (S/N)').Trim().ToUpper() -ne 'S') { return }
    if ($items.Name -contains 'Avast Free Antivirus') {
        Write-Warn2 'Avast desactiva Microsoft Defender automáticamente al instalarse (es normal). Durante la instalación puede ofrecer extras: revisa la app después.'
    }
    Install-Software $items
    Pause-Key
}

# ------------------------------------------------------------------
#  CUENTA LOCAL
# ------------------------------------------------------------------
function New-LocalAdmin {
    Clear-Host
    Write-Host "`n  === CREAR CUENTA LOCAL DE ADMINISTRADOR ===`n" -ForegroundColor Magenta
    Write-Host "  Usuario actual: $env:USERNAME  (tipo: $(Get-AccountType))`n"
    $name = (Read-Host '  Nombre de la nueva cuenta (vacío = cancelar)').Trim()
    if (-not $name) { return }
    if (Get-LocalUser -Name $name -ErrorAction SilentlyContinue) { Write-Err 'Ya existe un usuario con ese nombre.' ; Pause-Key ; return }
    $pw = Read-Host '  Contraseña (vacío = sin contraseña)' -AsSecureString
    try {
        if ($pw.Length -eq 0) { New-LocalUser -Name $name -NoPassword -ErrorAction Stop | Out-Null ; Set-LocalUser -Name $name -PasswordNeverExpires $true -ErrorAction SilentlyContinue }
        else { New-LocalUser -Name $name -Password $pw -PasswordNeverExpires -ErrorAction Stop | Out-Null }
        Add-LocalGroupMember -SID 'S-1-5-32-544' -Member $name -ErrorAction Stop   # Administradores (cualquier idioma)
        Write-Ok "Cuenta local '$name' creada como administrador."
        Write-Host ''
        Write-Host '  Pasos siguientes:' -ForegroundColor Cyan
        Write-Host "   1. Cierra sesión y entra con '$name'."
        Write-Host '   2. Copia tus archivos desde C:\Users\<tu usuario anterior>.'
        Write-Host '   3. Borra la cuenta Microsoft en Configuración > Cuentas > Otros usuarios.'
        Write-Host '   4. Vuelve a ejecutar este script y elige la opción 4 para bloquearlas del todo.'
    } catch { Write-Err "No se pudo crear la cuenta: $($_.Exception.Message)" }
    Pause-Key
}

function Block-MicrosoftAccountsFully {
    if ((Get-AccountType) -eq 'MicrosoftAccount') {
        Write-Err 'Estás usando una cuenta Microsoft: bloquearlas del todo te dejaría sin poder entrar. Crea primero una cuenta local (opción 3).'
        Pause-Key ; return
    }
    $msa = @(Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.PrincipalSource -eq 'MicrosoftAccount' -and $_.Enabled })
    if ($msa.Count -gt 0) {
        Write-Warn2 ("Estas cuentas Microsoft dejarán de poder iniciar sesión: " + ($msa.Name -join ', '))
        if ((Read-Host '  ¿Seguir? (S/N)').Trim().ToUpper() -ne 'S') { return }
    }
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'NoConnectedUser' 3
    Write-Ok 'Cuentas Microsoft bloqueadas por completo (ni añadir ni iniciar sesión).'
    Pause-Key
}

function New-Autounattend {
    Clear-Host
    Write-Host "`n  === GENERAR autounattend.xml ===`n" -ForegroundColor Magenta
    Write-Host '  Copia el archivo generado a la RAÍZ del USB de instalación de Windows 11.'
    Write-Host '  La instalación creará tu cuenta local y saltará la cuenta Microsoft y la red.'
    Write-Host '  Ojo: la contraseña queda en texto plano dentro del USB.' -ForegroundColor Yellow
    Write-Host ''
    $name = (Read-Host '  Nombre de usuario local').Trim()
    if (-not $name) { return }
    $pw = Read-Host '  Contraseña (vacío = sin contraseña)'
    if ("$name$pw" -match '[<>&"%^|]') { Write-Err 'No uses los caracteres < > & " % ^ | en nombre ni contraseña.' ; Pause-Key ; return }
    $lang = (Read-Host '  Idioma/región [es-ES]').Trim() ; if (-not $lang) { $lang = 'es-ES' }

    $firstLogon = ''
    if ($UpdateConfigured -and (Read-Host '  ¿Ejecutar este script automáticamente en el primer inicio? (S/N)').Trim().ToUpper() -eq 'S') {
        $firstLogon = @"
      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add">
          <Order>1</Order>
          <CommandLine>powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm '$InstallerUrl' | iex"</CommandLine>
          <Description>W11 Debloat</Description>
        </SynchronousCommand>
      </FirstLogonCommands>
"@
    }
    $pwArg = '""' ; if ($pw) { $pwArg = "`"$pw`"" }
    $autoLogon = ''
    if ($pw) {
        $autoLogon = @"
      <AutoLogon>
        <Username>$name</Username>
        <Enabled>true</Enabled>
        <LogonCount>1</LogonCount>
        <Password><Value>$pw</Value><PlainText>true</PlainText></Password>
      </AutoLogon>
"@
    } else {
        $autoLogon = @"
      <AutoLogon>
        <Username>$name</Username>
        <Enabled>true</Enabled>
        <LogonCount>1</LogonCount>
        <Password><Value></Value><PlainText>true</PlainText></Password>
      </AutoLogon>
"@
    }

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<!-- Generado por W11 Debloat $ScriptVersion -->
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <SetupUILanguage><UILanguage>$lang</UILanguage></SetupUILanguage>
      <InputLocale>$lang</InputLocale>
      <SystemLocale>$lang</SystemLocale>
      <UILanguage>$lang</UILanguage>
      <UserLocale>$lang</UserLocale>
    </component>
  </settings>
  <settings pass="specialize">
    <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <RunSynchronous>
        <RunSynchronousCommand wcm:action="add">
          <Order>1</Order>
          <Path>reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f</Path>
        </RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add">
          <Order>2</Order>
          <Path>net.exe user "$name" $pwArg /add</Path>
        </RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add">
          <Order>3</Order>
          <Path>powershell.exe -NoProfile -Command "Add-LocalGroupMember -SID 'S-1-5-32-544' -Member '$name'; Set-LocalUser -Name '$name' -PasswordNeverExpires `$true"</Path>
        </RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add">
          <Order>4</Order>
          <Path>reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v NoConnectedUser /t REG_DWORD /d 3 /f</Path>
        </RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add">
          <Order>5</Order>
          <Path>reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableWindowsConsumerFeatures /t REG_DWORD /d 1 /f</Path>
        </RunSynchronousCommand>
      </RunSynchronous>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <InputLocale>$lang</InputLocale>
      <SystemLocale>$lang</SystemLocale>
      <UILanguage>$lang</UILanguage>
      <UserLocale>$lang</UserLocale>
    </component>
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <HideWirelessSetupInOOBE>false</HideWirelessSetupInOOBE>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
$autoLogon$firstLogon    </component>
  </settings>
</unattend>
"@
    $desk = [Environment]::GetFolderPath('Desktop')
    $out = Join-Path $desk 'autounattend.xml'
    [IO.File]::WriteAllText($out, $xml, (New-Object System.Text.UTF8Encoding($false)))
    Write-Ok "Generado: $out"
    Write-Host '  Cópialo a la raíz del USB (junto a setup.exe). Necesitas un USB hecho con la ISO oficial (Rufus o Media Creation Tool).'
    Pause-Key
}

function Show-AccountMenu {
    while ($true) {
        Clear-Host
        Write-Host "`n  === CUENTA LOCAL ===`n" -ForegroundColor Magenta
        Write-Host "  Usuario actual: $env:USERNAME  (tipo: $(Get-AccountType))`n"
        Write-Host '  1. Crear cuenta local de administrador'
        Write-Host '  2. Bloquear cuentas Microsoft del todo (solo si ya usas cuenta local)'
        Write-Host '  3. Generar autounattend.xml para instalar W11 sin cuenta Microsoft'
        Write-Host '  0. Volver'
        switch ((Read-Host "`n  Opción").Trim()) {
            '1' { New-LocalAdmin }
            '2' { Block-MicrosoftAccountsFully }
            '3' { New-Autounattend }
            '0' { return }
        }
    }
}

# ------------------------------------------------------------------
#  Mantenimiento automático (tarea programada)
# ------------------------------------------------------------------
function Install-AutoTask {
    Clear-Host
    Write-Host "`n  === REAPLICAR AUTOMÁTICAMENTE ===`n" -ForegroundColor Magenta
    Write-Host '  Copia el script a C:\ProgramData\W11Debloat y crea una tarea que, al iniciar sesión,'
    Write-Host '  se actualiza (si hay versión nueva) y reaplica en silencio las categorías guardadas.'
    Write-Host '  Así, si una actualización de Windows reinstala basura o reactiva Copilot, se vuelve a quitar.'
    Write-Host ''
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        $r = (Read-Host '  La tarea ya existe. [Q]uitarla, [R]einstalarla o [0] volver').Trim().ToUpper()
        if ($r -eq 'Q') { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false ; Write-Ok 'Tarea eliminada.' ; Pause-Key ; return }
        if ($r -ne 'R') { return }
    } elseif ((Read-Host '  ¿Instalar? (S/N)').Trim().ToUpper() -ne 'S') { return }

    if (-not (Test-Path $ConfigFile)) { Save-Config (Get-Config).Categories }
    if ($PSCommandPath -ne $InstalledScript) { Copy-Item -LiteralPath $PSCommandPath -Destination $InstalledScript -Force }
    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$InstalledScript`" -Auto"
    $trigger   = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $trigger.Delay = 'PT2M'
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
    try {
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
        Write-Ok "Tarea '$TaskName' creada. Categorías: $(((Get-Config).Categories) -join ', ')"
        if (-not $UpdateConfigured) { Write-Warn2 'Sin $UpdateUrl configurada no habrá autoactualización, solo reaplicación.' }
    } catch { Write-Err "No se pudo crear la tarea: $($_.Exception.Message)" }
    Pause-Key
}

# ------------------------------------------------------------------
#  Arranque
# ------------------------------------------------------------------
$logDir = Join-Path $Root 'logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
Get-ChildItem $logDir -Filter '*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -Skip 15 | Remove-Item -Force -ErrorAction SilentlyContinue
try { Start-Transcript -Path (Join-Path $logDir ("{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))) -ErrorAction SilentlyContinue | Out-Null } catch {}

Update-Self

if ($Auto) {
    $keys = @((Get-Config).Categories)
    Invoke-Debloat $keys -Quiet
    try { Stop-Transcript | Out-Null } catch {}
    exit
}

while ($true) {
    Clear-Host
    Write-Host ''
    Write-Host '  ==============================================' -ForegroundColor Magenta
    Write-Host "     W11 DEBLOAT  v$ScriptVersion" -ForegroundColor Magenta
    Write-Host '  ==============================================' -ForegroundColor Magenta
    $upd = 'NO configurada (edita $UpdateUrl)' ; if ($UpdateConfigured) { $upd = 'activa' }
    $task = 'no' ; if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) { $task = 'sí' }
    Write-Host "  Usuario: $env:USERNAME ($(Get-AccountType))   Autoactualización: $upd   Reaplicar al iniciar: $task" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  1. Debloat RÁPIDO (categorías recomendadas)'
    Write-Host '  2. Debloat PERSONALIZADO (elegir categorías)'
    Write-Host '  3. Instalar software'
    Write-Host '  4. Cuenta local / autounattend.xml'
    Write-Host '  5. Reaplicar automáticamente tras actualizaciones de Windows'
    Write-Host '  6. Actualizar todos los programas instalados (winget upgrade)'
    Write-Host '  7. Crear punto de restauración'
    Write-Host '  0. Salir'
    switch ((Read-Host "`n  Opción").Trim()) {
        '1' {
            $keys = @($Categories | Where-Object Default | ForEach-Object Key)
            Save-Config $keys ; New-RestorePoint ; Invoke-Debloat $keys
            if ((Read-Host "`n  ¿Instalar ahora software? (S/N)").Trim().ToUpper() -eq 'S') { Show-SoftwareMenu } else { Pause-Key }
        }
        '2' { Show-DebloatMenu }
        '3' { Show-SoftwareMenu }
        '4' { Show-AccountMenu }
        '5' { Install-AutoTask }
        '6' {
            if (Ensure-Winget) { & winget upgrade --all --silent --accept-package-agreements --accept-source-agreements --include-unknown }
            Pause-Key
        }
        '7' { New-RestorePoint ; Pause-Key }
        '0' { try { Stop-Transcript | Out-Null } catch {} ; exit }
    }
}
