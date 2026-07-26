@echo off
setlocal EnableExtensions
chcp 65001 >nul
color 0B
title AutomationPlatform - Install Update Repair

set "TARGET_ROOT=D:\AutomationPlatform"
if not "%~1"=="" set "TARGET_ROOT=%~1"
if "%TARGET_ROOT:~-1%"=="\" set "TARGET_ROOT=%TARGET_ROOT:~0,-1%"

set "REPO_RAW=https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main"
set "MANIFEST_URL=%REPO_RAW%/platform_manifest.json"
set "TEMP_BOOT=%TEMP%\AutomationPlatform_Bootstrap"
set "RUNNER=%TEMP_BOOT%\BOOTSTRAP_RUNNER.ps1"
set "LATEST_LOG=%TARGET_ROOT%\logs\latest_bootstrap.log"
set "PYTHON_LOG=%TARGET_ROOT%\logs\latest_python_runtime.log"
set "CHROME_LOG=%TARGET_ROOT%\logs\latest_chrome_runtime.log"

if not exist "%TARGET_ROOT%" mkdir "%TARGET_ROOT%" 2>nul
if not exist "%TARGET_ROOT%\logs" mkdir "%TARGET_ROOT%\logs" 2>nul
if not exist "%TEMP_BOOT%" mkdir "%TEMP_BOOT%" 2>nul

echo.
echo ============================================================
echo   AutomationPlatform - INSTALL / UPDATE / REPAIR
echo ============================================================
echo   Root : %TARGET_ROOT%
echo   Repo : github.com/1777maxim7771/AutomationPlatform
echo.
echo   This BAT always downloads the newest bootstrap logic.
echo   Existing healthy components are skipped automatically.
echo   Missing, broken or outdated components are repaired/updated.
echo ============================================================
echo.

where powershell.exe >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Windows PowerShell was not found.
    pause
    exit /b 1
)

echo [BOOTSTRAP] Downloading latest BOOTSTRAP_RUNNER.ps1 from GitHub...

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; "^
  "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; "^
  "$u='%REPO_RAW%/BOOTSTRAP_RUNNER.ps1?nocache=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); "^
  "$d='%RUNNER%'; "^
  "New-Item -ItemType Directory -Force -Path (Split-Path -Parent $d) | Out-Null; "^
  "Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $d; "^
  "if (-not (Test-Path $d)) { throw 'BOOTSTRAP_RUNNER.ps1 was not downloaded.' }"

if errorlevel 1 (
    echo [ERROR] Cannot download bootstrap runner from GitHub.
    echo         Check Internet access.
    pause
    exit /b 2
)

if not exist "%RUNNER%" (
    echo [ERROR] Missing downloaded bootstrap runner: %RUNNER%
    pause
    exit /b 2
)

echo [BOOTSTRAP] Starting latest install/update/repair logic...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%RUNNER%" -Root "%TARGET_ROOT%" -ManifestUrl "%MANIFEST_URL%"
set "RC=%ERRORLEVEL%"

echo.
if not "%RC%"=="0" (
    echo ============================================================
    echo [ERROR] AutomationPlatform operation failed. Exit code %RC%
    echo [LOGS ] %TARGET_ROOT%\logs
    echo [BOOT ] %LATEST_LOG%
    echo [PY   ] %PYTHON_LOG%
    echo [CHROME] %CHROME_LOG%
    echo ============================================================
    echo.
    if exist "%PYTHON_LOG%" (
        echo --------------- PYTHON RUNTIME DIAGNOSTICS -------------
        powershell.exe -NoProfile -Command "Get-Content -Path '%PYTHON_LOG%' -Tail 80 -ErrorAction SilentlyContinue"
        echo ---------------------------------------------------------
        echo.
    )
    if exist "%CHROME_LOG%" (
        echo ---------------- CHROME RUNTIME DIAGNOSTICS -------------
        powershell.exe -NoProfile -Command "Get-Content -Path '%CHROME_LOG%' -Tail 80 -ErrorAction SilentlyContinue"
        echo ---------------------------------------------------------
        echo.
    )
    if exist "%LATEST_LOG%" (
        echo ----------------- BOOTSTRAP DIAGNOSTICS -----------------
        powershell.exe -NoProfile -Command "Get-Content -Path '%LATEST_LOG%' -Tail 80 -ErrorAction SilentlyContinue"
        echo ---------------------------------------------------------
    ) else (
        echo [WARN] latest_bootstrap.log was not created.
    )
    echo.
    pause
    exit /b %RC%
)

echo ============================================================
echo [OK] AutomationPlatform is installed / updated / repaired.
echo [LOGS] %TARGET_ROOT%\logs
if exist "%TARGET_ROOT%\data\platform_status.json" echo [STATUS] %TARGET_ROOT%\data\platform_status.json
echo ============================================================
echo.

endlocal
exit /b 0
