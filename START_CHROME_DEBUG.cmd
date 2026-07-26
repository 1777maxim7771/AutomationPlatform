@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "CONFIG=%ROOT%\config\platform.json"
set "VALUES=%ROOT%\data\shared_values.json"
set "PROFILE=%ROOT%\browser\Chrome_Profile"
set "PORT=9222"
set "CHROME="
set "START_URL="

REM Optional URL supplied by GUI/CLI has highest priority.
if not "%~1"=="" set "START_URL=%~1"

REM Read platform config (Chrome path/profile/port) when available.
if exist "%CONFIG%" (
  for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "try { (Get-Content -Raw '%CONFIG%' | ConvertFrom-Json).chrome_exe } catch {''}"`) do set "CHROME=%%A"
  for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "try { (Get-Content -Raw '%CONFIG%' | ConvertFrom-Json).chrome_profile } catch {''}"`) do if not "%%A"=="" set "PROFILE=%%A"
  for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "try { (Get-Content -Raw '%CONFIG%' | ConvertFrom-Json).debug_port } catch {''}"`) do if not "%%A"=="" set "PORT=%%A"
)

REM If GUI/CLI did not supply a URL, read browser.start_url from shared values.
if not defined START_URL if exist "%VALUES%" (
  for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "try { $j=Get-Content -Raw '%VALUES%' ^| ConvertFrom-Json; [string]$j.values.'browser.start_url' } catch {''}"`) do set "START_URL=%%A"
)

REM Remove the historical ChatGPT hard-coded default. It is no longer a platform default.
if /I "!START_URL!"=="https://chatgpt.com" set "START_URL="
if /I "!START_URL!"=="https://chatgpt.com/" set "START_URL="

REM Ask the user only when no URL is configured anywhere.
if not defined START_URL (
  echo.
  echo ============================================================
  echo  AutomationPlatform - Chrome Debug
  echo ============================================================
  echo  No start website is configured.
  echo  Enter a website to open in the Debug browser.
  echo  Example: example.com  or  https://example.com/path
  echo.
  set /p "START_URL=Website: "
)

if not defined START_URL (
  echo [CANCELLED] No website was specified.
  endlocal
  exit /b 2
)

REM Add https:// when the user typed only a domain/host.
echo(!START_URL!| findstr /R /C:"://" >nul
if errorlevel 1 set "START_URL=https://!START_URL!"

REM Official Google Chrome only. Keep existing installation when present.
if not defined CHROME if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" set "CHROME=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not defined CHROME if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" set "CHROME=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
if not defined CHROME if exist "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe" set "CHROME=%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"

if not defined CHROME (
  echo [ERROR] Google Chrome was not found.
  echo Run: %ROOT%\UPDATE_PLATFORM.cmd
  pause
  endlocal
  exit /b 1
)

if not exist "%PROFILE%" mkdir "%PROFILE%"

echo.
echo ============================================================
echo  AutomationPlatform - Chrome Debug
 echo ============================================================
echo  Chrome : %CHROME%
echo  Profile: %PROFILE%
echo  CDP    : http://127.0.0.1:%PORT%
echo  URL    : !START_URL!
echo ============================================================
echo.

start "" "%CHROME%" ^
  --remote-debugging-port=%PORT% ^
  --remote-allow-origins=* ^
  --user-data-dir="%PROFILE%" ^
  --no-first-run ^
  --no-default-browser-check ^
  --disable-popup-blocking ^
  --disable-session-crashed-bubble ^
  --hide-crash-restore-bubble ^
  "!START_URL!"

endlocal
exit /b 0
