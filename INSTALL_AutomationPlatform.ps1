# AutomationPlatform bootstrap (avoids Windows blocking of downloaded .bat)
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr -useb https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/INSTALL_AutomationPlatform.ps1 | iex"
# Or download this file, then:
#   Unblock-File .\INSTALL_AutomationPlatform.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\INSTALL_AutomationPlatform.ps1

param(
    [string]$DefaultRoot = "D:\AutomationPlatform",
    [string]$ManifestUrl = "https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/platform_manifest.json"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoRaw = "https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main"
$tempDir = Join-Path $env:TEMP "AutomationPlatform_Bootstrap"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  AutomationPlatform — установка с GitHub" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Цель : $DefaultRoot"
Write-Host "  Repo : github.com/1777maxim7771/AutomationPlatform"
Write-Host ""

$installer = Join-Path $tempDir "START_PLATFORM_INSTALLER.ps1"
Write-Host "[1/3] Скачиваю START_PLATFORM_INSTALLER.ps1..." -ForegroundColor Yellow
Invoke-WebRequest -UseBasicParsing -Uri "$RepoRaw/START_PLATFORM_INSTALLER.ps1" -OutFile $installer

if (-not (Test-Path $installer)) {
    throw "Не удалось скачать START_PLATFORM_INSTALLER.ps1"
}

# Remove Mark-of-the-Web so Smart App Control / SmartScreen do not block it
try { Unblock-File -Path $installer -ErrorAction SilentlyContinue } catch {}

Write-Host "[2/3] Запускаю установщик (окно GUI)..." -ForegroundColor Yellow
Write-Host "      В окне нажмите «УСТАНОВИТЬ / ОБНОВИТЬ»." -ForegroundColor Gray
Write-Host ""

& $installer -DefaultRoot $DefaultRoot -ManifestUrl $ManifestUrl

Write-Host ""
Write-Host "[3/3] Готово." -ForegroundColor Green
Write-Host ""
Write-Host "Дальше:" -ForegroundColor Cyan
Write-Host "  Control Center : $DefaultRoot\START_CONTROL_CENTER.cmd"
Write-Host "  Обновление     : $DefaultRoot\UPDATE_PLATFORM.cmd"
Write-Host "  Логи           : $DefaultRoot\logs"
Write-Host ""
