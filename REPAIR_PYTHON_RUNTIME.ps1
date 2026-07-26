param(
    [string]$Root = "D:\AutomationPlatform",
    [string]$ManifestUrl = "https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/platform_manifest.json"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Step([string]$Text) {
    Write-Host "[AutomationPlatform][PYTHON-REPAIR] $Text" -ForegroundColor Cyan
}

$Root = $Root.Trim().Trim([char]0x22, [char]0x27).TrimEnd('\','/').Trim()
if (-not $Root) { throw "Root path is empty." }

$pythonExe = Join-Path $Root "runtime\python\python.exe"
$installerDir = Join-Path $Root "installer"
$tempDir = Join-Path $env:TEMP "AutomationPlatformPythonRepair"
$corePath = Join-Path $tempDir "INSTALLER_CORE.ps1"

New-Item -ItemType Directory -Force -Path $installerDir | Out-Null
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

function Test-Tkinter {
    if (-not (Test-Path $pythonExe)) { return $false }
    & $pythonExe -c "import tkinter; print(tkinter.TkVersion)" *> $null
    return ($LASTEXITCODE -eq 0)
}

if (Test-Tkinter) {
    Write-Step "tkinter is already available. No repair is required."
    exit 0
}

Write-Step "tkinter is missing from the project-local Python runtime."
Write-Step "Downloading the latest installer core from GitHub..."

$base = "https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/"
$stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$coreUrl = $base + "INSTALLER_CORE.ps1?nocache=" + $stamp
Invoke-WebRequest -UseBasicParsing -Uri $coreUrl -OutFile $corePath
Copy-Item -Force $corePath (Join-Path $installerDir "INSTALLER_CORE.ps1")

Write-Step "Reinstalling the local Python runtime as the full CPython distribution with Tcl/Tk..."
$args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $corePath,
    "-Root", $Root,
    "-ManifestUrl", $ManifestUrl,
    "-InstallPython",
    "-CreateChromeProfile"
)

$p = Start-Process -FilePath "powershell.exe" -ArgumentList $args -Wait -PassThru
if ($p.ExitCode -ne 0) {
    throw "Installer Core failed while repairing Python. Exit code: $($p.ExitCode)"
}

if (-not (Test-Path $pythonExe)) {
    throw "Python repair finished but python.exe was not found: $pythonExe"
}

if (-not (Test-Tkinter)) {
    throw "Python was repaired, but tkinter is still unavailable. See D:\AutomationPlatform\logs for the latest install log."
}

Write-Step "Repair completed successfully. tkinter is available."
& $pythonExe -c "import tkinter; print('Python tkinter OK; Tk version:', tkinter.TkVersion)"
exit 0
