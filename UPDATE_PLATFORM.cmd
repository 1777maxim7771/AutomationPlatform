@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "BAT=%ROOT%\INSTALL_AutomationPlatform.bat"
set "RAW=https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/INSTALL_AutomationPlatform.bat"

if not exist "%BAT%" (
    echo [UPDATE] Local universal BAT is missing. Downloading it from GitHub...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
      "$ErrorActionPreference='Stop'; "^
      "$u='%RAW%?nocache=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); "^
      "Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile '%BAT%'"
    if errorlevel 1 (
        echo [ERROR] Could not download INSTALL_AutomationPlatform.bat
        pause
        exit /b 1
    )
)

call "%BAT%" "%ROOT%"
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%
