@echo off
setlocal EnableExtensions
cd /d "%~dp0"

REM %~dp0 always ends with \  —  "D:\path\" escapes the closing quote in PowerShell.
REM Strip the trailing backslash before passing -DefaultRoot.
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

if not exist "%ROOT%\installer\START_PLATFORM_INSTALLER.ps1" (
  echo [ERROR] Missing: installer\START_PLATFORM_INSTALLER.ps1
  echo Run the bootstrap installer once, or download files from GitHub.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\installer\START_PLATFORM_INSTALLER.ps1" -DefaultRoot "%ROOT%"
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%
