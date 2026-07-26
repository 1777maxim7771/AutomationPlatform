@echo off
setlocal EnableExtensions
chcp 65001 >nul
title AutomationPlatform - Bootstrap Installer
color 0B

set "TARGET_ROOT=D:\AutomationPlatform"
set "REPO_RAW=https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main"
set "MANIFEST_URL=%REPO_RAW%/platform_manifest.json"
set "TEMP_BOOT=%TEMP%\AutomationPlatform_Bootstrap"
set "PS1_FILE=%TEMP_BOOT%\START_PLATFORM_INSTALLER.ps1"

echo.
echo ============================================================
echo   AutomationPlatform - install from GitHub
echo ============================================================
echo.
echo   Target : %TARGET_ROOT%
echo   Repo   : github.com/1777maxim7771/AutomationPlatform
echo.
echo ------------------------------------------------------------
echo   1. Create folder
echo   2. Download installer scripts
echo   3. Python + Chrome + Control Center + profile
echo   4. Show next steps
echo ------------------------------------------------------------
echo.

where powershell >nul 2>nul
if errorlevel 1 (
    echo [ERROR] PowerShell not found.
    pause
    exit /b 1
)

echo [1/4] Temp folder...
if exist "%TEMP_BOOT%" rmdir /s /q "%TEMP_BOOT%" 2>nul
mkdir "%TEMP_BOOT%" 2>nul
if not exist "%TEMP_BOOT%" (
    echo [ERROR] Cannot create %TEMP_BOOT%
    pause
    exit /b 2
)

echo [2/4] Download START_PLATFORM_INSTALLER.ps1 ...

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $d = Join-Path $env:TEMP 'AutomationPlatform_Bootstrap'; New-Item -ItemType Directory -Force -Path $d | Out-Null; $f = Join-Path $d 'START_PLATFORM_INSTALLER.ps1'; $r = Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/START_PLATFORM_INSTALLER.ps1'; $enc = New-Object System.Text.UTF8Encoding $true; [System.IO.File]::WriteAllText($f, $r.Content, $enc); Unblock-File $f -ErrorAction SilentlyContinue; if (Test-Path $f) { exit 0 } else { exit 1 }"

if errorlevel 1 (
    echo [ERROR] Download failed. Check internet / GitHub access.
    pause
    exit /b 3
)

if not exist "%PS1_FILE%" (
    echo [ERROR] Installer file missing after download.
    pause
    exit /b 3
)

echo [3/4] Starting installer GUI...
echo       Root: %TARGET_ROOT%
echo       Press INSTALL / UPDATE in the window.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1_FILE%" -DefaultRoot "%TARGET_ROOT%" -ManifestUrl "%MANIFEST_URL%"
set "RC=%ERRORLEVEL%"

echo.
echo [4/4] Done
echo ------------------------------------------------------------
if not "%RC%"=="0" (
    echo [ERROR] Installer exit code %RC%
    pause
    exit /b %RC%
)

echo [OK] Install finished.
echo.
echo Next steps:
echo   Control Center : %TARGET_ROOT%\START_CONTROL_CENTER.cmd
echo   Update         : %TARGET_ROOT%\UPDATE_PLATFORM.cmd
echo   Logs           : %TARGET_ROOT%\logs
echo.

if exist "%TARGET_ROOT%\START_CONTROL_CENTER.cmd" (
    choice /C YN /M "Open Control Center now"
    if not errorlevel 2 start "" "%TARGET_ROOT%\START_CONTROL_CENTER.cmd"
)

echo.
pause
endlocal
exit /b 0
