param(
    [string]$Root = "D:\AutomationPlatform",
    [string]$ManifestUrl = "https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/platform_manifest.json",
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root = $Root.Trim().Trim([char]0x22, [char]0x27).TrimEnd('\','/').Trim()
if (-not $Root) { throw "Root path is empty." }

$RepoRaw = "https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main"
$logDir = Join-Path $Root "logs"
$installerDir = Join-Path $Root "installer"
$tempDir = Join-Path $env:TEMP "AutomationPlatform_Bootstrap"
New-Item -ItemType Directory -Force -Path $Root,$logDir,$installerDir,$tempDir | Out-Null

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $logDir "bootstrap_$stamp.log"
$latestLog = Join-Path $logDir "latest_bootstrap.log"

function Log([string]$Text, [string]$Level = "INFO") {
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Text
    Write-Host $line
    Add-Content -Encoding UTF8 -Path $logFile -Value $line
}

function Download([string]$Url, [string]$Dest) {
    $sep = if ($Url -match '\?') { '&' } else { '?' }
    $fetchUrl = "$Url$sep`nocache=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
    Log "DOWNLOAD $fetchUrl"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dest) | Out-Null
    Invoke-WebRequest -UseBasicParsing -Uri $fetchUrl -OutFile $Dest
    if (-not (Test-Path $Dest)) { throw "Download failed: $Url" }
    Log ("DOWNLOADED {0} bytes -> {1}" -f (Get-Item $Dest).Length, $Dest)
}

"=== AutomationPlatform bootstrap $stamp ===" | Set-Content -Encoding UTF8 $logFile
Log "Root=$Root"
Log "Manifest=$ManifestUrl"
Log "Mode=INSTALL_OR_UPDATE_OR_REPAIR"

try {
    $manifestFile = Join-Path $tempDir "platform_manifest.json"
    $coreFile = Join-Path $tempDir "INSTALLER_CORE.ps1"

    Log "Fetching latest manifest and installer core from GitHub"
    Download $ManifestUrl $manifestFile
    $manifest = Get-Content -Raw -Encoding UTF8 $manifestFile | ConvertFrom-Json
    Log "Manifest schema=$($manifest.schema_version), ControlCenter=$($manifest.control_center.version), Python=$($manifest.python.version)"

    Download "$RepoRaw/INSTALLER_CORE.ps1" $coreFile
    Copy-Item -Force $coreFile (Join-Path $installerDir "INSTALLER_CORE.ps1")
    Copy-Item -Force $manifestFile (Join-Path $installerDir "platform_manifest.json")

    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $coreFile,
        '-Root', $Root,
        '-ManifestUrl', $ManifestUrl,
        '-InstallPython',
        '-InstallChrome',
        '-InstallControlCenter',
        '-CreateChromeProfile'
    )

    Log "Starting Installer Core"
    $coreOutput = & powershell.exe @args 2>&1
    $coreExit = $LASTEXITCODE
    foreach ($line in $coreOutput) {
        $text = [string]$line
        Write-Host $text
        Add-Content -Encoding UTF8 -Path $logFile -Value "[CORE] $text"
    }

    if ($coreExit -ne 0) {
        throw "Installer Core failed with exit code $coreExit"
    }

    $statusPath = Join-Path $Root "data\platform_status.json"
    if (Test-Path $statusPath) {
        try {
            $status = Get-Content -Raw -Encoding UTF8 $statusPath | ConvertFrom-Json
            Log "Health overall=$($status.overall_status)"
            Log "Python status=$($status.components.python.status), version=$($status.components.python.installed_version), tkinter=$($status.components.python.tkinter)"
            Log "Chrome status=$($status.components.chrome.status), version=$($status.components.chrome.installed_version)"
            Log "ControlCenter status=$($status.components.control_center.status), version=$($status.components.control_center.installed_version)"
        } catch {
            Log "Could not parse platform_status.json: $($_.Exception.Message)" "WARN"
        }
    }

    Copy-Item -Force $logFile $latestLog
    Log "Bootstrap completed successfully"

    if (-not $NoLaunch) {
        $launcher = Join-Path $Root "START_CONTROL_CENTER.cmd"
        if (Test-Path $launcher) {
            Log "Launching Control Center: $launcher"
            Start-Process -FilePath $launcher -WorkingDirectory $Root
        } else {
            Log "Control Center launcher missing after successful install: $launcher" "WARN"
        }
    }

    exit 0
}
catch {
    Log "FATAL: $($_.Exception.Message)" "ERROR"
    try { Log $_.ScriptStackTrace "ERROR" } catch {}
    try { Copy-Item -Force $logFile $latestLog } catch {}
    Write-Host ""
    Write-Host "[ERROR] AutomationPlatform setup/update failed." -ForegroundColor Red
    Write-Host "Log: $logFile" -ForegroundColor Yellow
    exit 1
}
