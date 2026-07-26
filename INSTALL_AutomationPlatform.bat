@echo off
setlocal EnableExtensions
chcp 65001 >nul
color 0B
title AutomationPlatform - Smart Bootstrap

set "TARGET_ROOT=D:\AutomationPlatform"
if not "%~1"=="" set "TARGET_ROOT=%~1"
if "%TARGET_ROOT:~-1%"=="\" set "TARGET_ROOT=%TARGET_ROOT:~0,-1%"

set "REPO_RAW=https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main"
set "MANIFEST_URL=%REPO_RAW%/platform_manifest.json"
set "TEMP_BOOT=%TEMP%\AutomationPlatform_Bootstrap"
set "GUI=%TEMP_BOOT%\START_PLATFORM_INSTALLER.ps1"
set "LATEST_LOG=%TARGET_ROOT%\logs\latest_bootstrap.log"

if not exist "%TARGET_ROOT%" mkdir "%TARGET_ROOT%" 2>nul
if not exist "%TARGET_ROOT%\logs" mkdir "%TARGET_ROOT%\logs" 2>nul
if not exist "%TEMP_BOOT%" mkdir "%TEMP_BOOT%" 2>nul

where powershell.exe >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Windows PowerShell was not found.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo   AutomationPlatform - SMART INSTALL / UPDATE / REPAIR
echo ============================================================
echo   Root : %TARGET_ROOT%
echo   Repo : github.com/1777maxim7771/AutomationPlatform
echo.
echo   1. Refresh latest lightweight GUI from GitHub
echo   2. GUI refreshes the latest bootstrap engine
echo   3. Healthy components are skipped automatically
echo ============================================================
echo.
echo [UI] Downloading latest installer interface...

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; "^
  "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; "^
  "$u='%REPO_RAW%/START_PLATFORM_INSTALLER.ps1?nocache=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); "^
  "$d='%GUI%'; "^
  "New-Item -ItemType Directory -Force -Path (Split-Path -Parent $d) | Out-Null; "^
  "Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $d; "^
  "if (-not (Test-Path $d)) { throw 'Installer UI was not downloaded.' }"

if errorlevel 1 (
    echo [ERROR] Cannot download the latest installer UI from GitHub.
    echo         Check Internet access.
    pause
    exit /b 2
)

echo [UI] Starting latest dynamic interface...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%GUI%" -DefaultRoot "%TARGET_ROOT%" -ManifestUrl "%MANIFEST_URL%"
set "RC=%ERRORLEVEL%"

if not "%RC%"=="0" (
    echo.
    echo ============================================================
    echo [ERROR] AutomationPlatform UI/bootstrap returned %RC%
    echo [LOG  ] %LATEST_LOG%
    echo ============================================================
    if exist "%LATEST_LOG%" powershell.exe -NoProfile -Command "Get-Content -Path '%LATEST_LOG%' -Tail 80 -ErrorAction SilentlyContinue"
    echo.
    pause
    exit /b %RC%
)

endlocal
exit /b 0
