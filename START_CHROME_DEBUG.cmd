@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "PROFILE=%ROOT%\browser\Chrome_Profile"
set "PORT=9222"
set "START_URL=https://chatgpt.com"
set "CHROME="

REM Prefer chrome_exe from platform.json (must be official Google Chrome)
if exist "%ROOT%\config\platform.json" (
  for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "try { (Get-Content -Raw '%ROOT%\config\platform.json' | ConvertFrom-Json).chrome_exe } catch {''}"`) do set "CHROME=%%A"
)

REM Official Google Chrome only (no Chrome for Testing)
if not defined CHROME if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" set "CHROME=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not defined CHROME if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" set "CHROME=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
if not defined CHROME if exist "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe" set "CHROME=%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"

if not defined CHROME (
  echo [ERROR] Official Google Chrome was not found.
  echo Chrome for Testing is not used by this platform.
  echo.
  echo Install Google Chrome, then run:
  echo   %ROOT%\UPDATE_PLATFORM.cmd
  pause
  exit /b 1
)

if not exist "%PROFILE%" mkdir "%PROFILE%"

echo ============================================================
echo  AutomationPlatform - Chrome Debug
echo ============================================================
echo  Chrome : %CHROME%
echo  Profile: %PROFILE%
echo  Port   : %PORT%
echo  URL    : %START_URL%
echo ============================================================
echo.
echo  Log in to ChatGPT once in this window.
echo  Session is stored in the platform profile.
echo  CDP: http://127.0.0.1:%PORT%
echo.

start "" "%CHROME%" ^
  --remote-debugging-port=%PORT% ^
  --remote-allow-origins=* ^
  --user-data-dir="%PROFILE%" ^
  --no-first-run ^
  --no-default-browser-check ^
  --disable-popup-blocking ^
  "%START_URL%"

endlocal
exit /b 0
