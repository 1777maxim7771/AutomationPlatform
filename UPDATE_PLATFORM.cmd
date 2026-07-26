@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "TEMPBAT=%TEMP%\AutomationPlatform_Bootstrap\INSTALL_AutomationPlatform.bat"
set "RAW=https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/INSTALL_AutomationPlatform.bat"

if not exist "%TEMP%\AutomationPlatform_Bootstrap" mkdir "%TEMP%\AutomationPlatform_Bootstrap" >nul 2>nul

echo [UPDATE] Downloading latest universal BAT from GitHub...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; "^
  "$u='%RAW%?nocache=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); "^
  "Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile '%TEMPBAT%'"

if errorlevel 1 (
    echo [ERROR] Could not download latest INSTALL_AutomationPlatform.bat
    pause
    exit /b 1
)

call "%TEMPBAT%" "%ROOT%"
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%
