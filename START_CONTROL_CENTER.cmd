@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "PROFILE=%ROOT%\browser\Chrome_Profile"
set "CONFIG=%ROOT%\config\platform.json"
set "CC_DIR=%ROOT%\control_center"
set "LOGDIR=%ROOT%\logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"

echo ============================================================
echo  AutomationPlatform - Control Center
echo ============================================================
echo  Root: %ROOT%
echo.

REM ---- Resolve Python ----
set "PYTHON="
if exist "%CONFIG%" (
  for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "try { (Get-Content -Raw '%CONFIG%' | ConvertFrom-Json).python_exe } catch {''}"`) do set "PYTHON=%%A"
)
if not defined PYTHON if exist "%ROOT%\runtime\python\python.exe" set "PYTHON=%ROOT%\runtime\python\python.exe"
if not defined PYTHON (
  where python >nul 2>&1 && for /f "delims=" %%A in ('where python') do (
    set "PYTHON=%%A"
    goto :py_found
  )
)
:py_found

if not defined PYTHON (
  echo [ERROR] Python not found.
  echo.
  echo Control Center needs local Python.
  echo Fix:
  echo   1^) Run  %ROOT%\UPDATE_PLATFORM.cmd
  echo   2^) Ensure checkbox "Local Python runtime" is ON
  echo   3^) Check:  %ROOT%\runtime\python\python.exe --version
  echo.
  pause
  exit /b 1
)

if not exist "%PYTHON%" (
  echo [ERROR] python_exe path does not exist:
  echo   %PYTHON%
  echo.
  echo Run UPDATE_PLATFORM.cmd to repair Python install.
  pause
  exit /b 1
)

echo  Python : %PYTHON%
"%PYTHON%" --version 2>nul
if errorlevel 1 (
  echo [ERROR] Python failed to start.
  pause
  exit /b 1
)

REM ---- Resolve official Google Chrome ----
set "CHROME="
if exist "%CONFIG%" (
  for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "try { (Get-Content -Raw '%CONFIG%' | ConvertFrom-Json).chrome_exe } catch {''}"`) do set "CHROME=%%A"
)
if not defined CHROME if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" set "CHROME=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not defined CHROME if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" set "CHROME=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
if not defined CHROME if exist "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe" set "CHROME=%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"

if not defined CHROME (
  echo [ERROR] Official Google Chrome not found.
  echo Chrome for Testing is not used.
  echo Install Google Chrome, then run UPDATE_PLATFORM.cmd
  pause
  exit /b 1
)
echo  Chrome : %CHROME%

if not exist "%PROFILE%" mkdir "%PROFILE%"
echo  Profile: %PROFILE%

REM ---- Control Center package present? ----
if not exist "%CC_DIR%" (
  echo [ERROR] Folder missing: control_center\
  echo Re-run UPDATE_PLATFORM.cmd with "Install / update Control Center" enabled.
  pause
  exit /b 1
)

REM ---- Find entry script ----
set "ENTRY="
for %%F in (
  "%CC_DIR%\main.py"
  "%CC_DIR%\app.py"
  "%CC_DIR%\control_center.py"
  "%CC_DIR%\__main__.py"
  "%ROOT%\core\main.py"
  "%ROOT%\core\app.py"
) do (
  if exist %%~F if not defined ENTRY set "ENTRY=%%~F"
)

if not defined ENTRY (
  echo [ERROR] No Control Center entry script found.
  echo Expected one of: control_center\main.py / app.py / control_center.py
  echo.
  echo Contents of control_center:
  dir /b "%CC_DIR%" 2>nul
  echo.
  echo The Control Center package may be incomplete.
  echo Re-run UPDATE_PLATFORM.cmd or reinstall Control Center package.
  pause
  exit /b 1
)

echo  Entry  : %ENTRY%
echo ============================================================
echo.

set "PYTHONPATH=%ROOT%;%CC_DIR%;%ROOT%\core;%PYTHONPATH%"
set "AUTOMATION_PLATFORM_ROOT=%ROOT%"
set "AUTOMATION_PLATFORM_CONFIG=%CONFIG%"

"%PYTHON%" "%ENTRY%"
set "RC=%ERRORLEVEL%"

if not "%RC%"=="0" (
  echo.
  echo [ERROR] Control Center exited with code %RC%
  echo Check logs in: %LOGDIR%
  pause
  exit /b %RC%
)

endlocal
exit /b 0
