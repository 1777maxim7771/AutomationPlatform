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
    $pythonManagerFile = Join-Path $tempDir "PYTHON_RUNTIME_MANAGER.ps1"
    $coreFile = Join-Path $tempDir "INSTALLER_CORE.ps1"

    Log "Fetching latest manifest and bootstrap components from GitHub"
    Download $ManifestUrl $manifestFile
    $manifest = Get-Content -Raw -Encoding UTF8 $manifestFile | ConvertFrom-Json
    Log "Manifest schema=$($manifest.schema_version), ControlCenter=$($manifest.control_center.version), Python=$($manifest.python.version), PythonMethod=$($manifest.python.method)"

    Download "$RepoRaw/PYTHON_RUNTIME_MANAGER.ps1" $pythonManagerFile
    Download "$RepoRaw/INSTALLER_CORE.ps1" $coreFile
    Copy-Item -Force $pythonManagerFile (Join-Path $installerDir "PYTHON_RUNTIME_MANAGER.ps1")
    Copy-Item -Force $coreFile (Join-Path $installerDir "INSTALLER_CORE.ps1")
    Copy-Item -Force $manifestFile (Join-Path $installerDir "platform_manifest.json")

    # Python is deliberately handled BEFORE Installer Core using the official
    # PythonCore runtime ZIP. This avoids the Windows EXE installer's global
    # product-registration behaviour and keeps Python application-local.
    $pyArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $pythonManagerFile,
        '-Root', $Root,
        '-ManifestUrl', $ManifestUrl
    )

    Log "Starting application-local Python Runtime Manager"
    & powershell.exe @pyArgs 2>&1 | ForEach-Object {
        $text = [string]$_
        Write-Host $text
        Add-Content -Encoding UTF8 -Path $logFile -Value "[PYTHON-RUNTIME] $text"
    }
    $pyExit = $LASTEXITCODE
    if ($pyExit -ne 0) {
        throw "Python Runtime Manager failed with exit code $pyExit"
    }

    # Python is already healthy now. Installer Core checks it again, but it is
    # not allowed to reinstall it through the legacy EXE path.
    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $coreFile,
        '-Root', $Root,
        '-ManifestUrl', $ManifestUrl,
        '-InstallChrome',
        '-InstallControlCenter',
        '-CreateChromeProfile'
    )

    Log "Starting Installer Core (Python pre-verified; legacy Python install disabled)"
    & powershell.exe @args 2>&1 | ForEach-Object {
        $text = [string]$_
        Write-Host $text
        Add-Content -Encoding UTF8 -Path $logFile -Value "[CORE] $text"
    }
    $coreExit = $LASTEXITCODE

    if ($coreExit -ne 0) {
        throw "Installer Core failed with exit code $coreExit"
    }

    $statusPath = Join-Path $Root "data\platform_status.json"
    if (Test-Path $statusPath) {
        try {
            $status = Get-Content -Raw -Encoding UTF8 $statusPath | ConvertFrom-Json
            Log "Health overall=$($status.overall_status)"
            Log "Python status=$($status.components.python.status), action=$($status.components.python.action), version=$($status.components.python.installed_version), tkinter=$($status.components.python.tkinter)"
            Log "Chrome status=$($status.components.chrome.status), action=$($status.components.chrome.action), version=$($status.components.chrome.installed_version)"
            Log "ControlCenter status=$($status.components.control_center.status), action=$($status.components.control_center.action), version=$($status.components.control_center.installed_version)"
        } catch {
            Log "Could not parse platform_status.json: $($_.Exception.Message)" "WARN"
        }
    }

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

    Copy-Item -Force $logFile $latestLog
    exit 0
}
catch {
    Log "FATAL: $($_.Exception.Message)" "ERROR"
    try { Log $_.ScriptStackTrace "ERROR" } catch {}
    try { Copy-Item -Force $logFile $latestLog } catch {}
    Write-Host ""
    Write-Host "[ERROR] AutomationPlatform setup/update failed." -ForegroundColor Red
    Write-Host "Log: $logFile" -ForegroundColor Yellow
    $pyLatest = Join-Path $logDir "latest_python_runtime.log"
    if (Test-Path $pyLatest) { Write-Host "Python runtime log: $pyLatest" -ForegroundColor Yellow }
    exit 1
}
