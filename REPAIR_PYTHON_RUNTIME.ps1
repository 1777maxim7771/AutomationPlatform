param(
    [string]$Root = "D:\AutomationPlatform",
    [string]$ManifestUrl = "https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/platform_manifest.json"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root = $Root.Trim().Trim([char]0x22,[char]0x27).TrimEnd('\','/').Trim()
if (-not $Root) { throw "Root path is empty." }

$installerDir = Join-Path $Root "installer"
$tempDir = Join-Path $env:TEMP "AutomationPlatformPythonRepair"
$managerPath = Join-Path $tempDir "PYTHON_RUNTIME_MANAGER.ps1"
$localManager = Join-Path $installerDir "PYTHON_RUNTIME_MANAGER.ps1"
$base = "https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main"

New-Item -ItemType Directory -Force -Path $installerDir,$tempDir | Out-Null

Write-Host "[AutomationPlatform][PYTHON-REPAIR] Downloading latest portable Python Runtime Manager..." -ForegroundColor Cyan
$u = "$base/PYTHON_RUNTIME_MANAGER.ps1?nocache=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $managerPath
if (-not (Test-Path $managerPath)) { throw "PYTHON_RUNTIME_MANAGER.ps1 was not downloaded." }
Copy-Item -Force $managerPath $localManager

Write-Host "[AutomationPlatform][PYTHON-REPAIR] Checking / installing / updating / repairing application-local Python..." -ForegroundColor Cyan
& powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File $managerPath `
    -Root $Root `
    -ManifestUrl $ManifestUrl

$rc = $LASTEXITCODE
if ($rc -ne 0) {
    throw "Python Runtime Manager failed with exit code $rc. See $Root\logs\latest_python_runtime.log"
}

$pythonExe = Join-Path $Root "runtime\python\python.exe"
if (-not (Test-Path $pythonExe)) { throw "python.exe is missing after runtime repair: $pythonExe" }

& $pythonExe -c "import sys, tkinter; print('Python', sys.version.split()[0], '| Tk', tkinter.TkVersion)"
if ($LASTEXITCODE -ne 0) { throw "Final Python/tkinter check failed after runtime repair." }

Write-Host "[AutomationPlatform][PYTHON-REPAIR] Repair completed successfully." -ForegroundColor Green
exit 0
