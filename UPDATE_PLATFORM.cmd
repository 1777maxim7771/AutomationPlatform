@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "INSTALLER=%ROOT%\installer"
if not exist "%INSTALLER%" mkdir "%INSTALLER%"

echo ============================================================
echo  AutomationPlatform - UPDATE
echo  Pulling latest installer from GitHub, then installing...
echo ============================================================
echo  Root: %ROOT%
echo.

REM Always refresh installer scripts BEFORE running them.
REM Otherwise an old local INSTALLER_CORE can skip Python/tkinter repair.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; "^
  "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; "^
  "$base='https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/'; "^
  "$t=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); "^
  "$dest='%INSTALLER%'; "^
  "New-Item -ItemType Directory -Force -Path $dest | Out-Null; "^
  "@('START_PLATFORM_INSTALLER.ps1','INSTALLER_CORE.ps1','START_INSTALLER_GUI.cmd','REPAIR_PYTHON_RUNTIME.ps1') | ForEach-Object { "^
  "  $url = $base + $_ + '?nocache=' + $t; "^
  "  $out = Join-Path $dest $_; "^
  "  Write-Host ('  Download: ' + $_); "^
  "  Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $out; "^
  "}; "^
  "Write-Host '  Installer and repair scripts updated.';"

if errorlevel 1 (
  echo [ERROR] Failed to download installer scripts from GitHub.
  echo Check internet access and try again.
  pause
  exit /b 1
)

if not exist "%INSTALLER%\START_PLATFORM_INSTALLER.ps1" (
  echo [ERROR] Missing: installer\START_PLATFORM_INSTALLER.ps1
  pause
  exit /b 1
)

echo.
echo Launching installer GUI...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%\START_PLATFORM_INSTALLER.ps1" -DefaultRoot "%ROOT%"
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%
