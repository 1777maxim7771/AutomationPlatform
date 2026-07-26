param(
    [string]$DefaultRoot = "D:\AutomationPlatform",
    [string]$ManifestUrl = "https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/platform_manifest.json"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$raw = "https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/INSTALLER_UI.ps1"
$tempDir = Join-Path $env:TEMP "AutomationPlatform_Bootstrap"
$ui = Join-Path $tempDir "INSTALLER_UI.ps1"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
$url = $raw + "?nocache=" + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $ui
if (-not (Test-Path $ui)) { throw "INSTALLER_UI.ps1 was not downloaded." }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ui -DefaultRoot $DefaultRoot -ManifestUrl $ManifestUrl
exit $LASTEXITCODE
