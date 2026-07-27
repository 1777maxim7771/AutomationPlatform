@echo off
REM AutomationPlatform START_CONTROL_CENTER.cmd v20260727-shell1
setlocal EnableExtensions
cd /d "%~dp0"

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "PROFILE=%ROOT%\browser\Chrome_Profile"
set "CONFIG=%ROOT%\config\platform.json"
set "CC_DIR=%ROOT%\control_center"
set "LOGDIR=%ROOT%\logs"
set "INSTALLERDIR=%ROOT%\installer"
set "REPAIR=%INSTALLERDIR%\REPAIR_PYTHON_RUNTIME.ps1"
set "PYTHON_RUNTIME=%ROOT%\runtime\python\python.exe"
set "SHELL_ENTRY=%CC_DIR%\shell.py"

if not exist "%LOGDIR%" mkdir "%LOGDIR%"
if not exist "%INSTALLERDIR%" mkdir "%INSTALLERDIR%"
if not exist "%CC_DIR%" mkdir "%CC_DIR%"

set "PYTHON="
if exist "%CONFIG%" (
  for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "try { (Get-Content -Raw '%CONFIG%' | ConvertFrom-Json).python_exe } catch {''}"`) do set "PYTHON=%%A"
)
if not defined PYTHON if exist "%PYTHON_RUNTIME%" set "PYTHON=%PYTHON_RUNTIME%"

if not defined PYTHON (
  echo [ERROR] Python not found. Run UPDATE_PLATFORM.cmd
  pause
  exit /b 1
)
if not exist "%PYTHON%" (
  echo [ERROR] Missing: %PYTHON%
  pause
  exit /b 1
)

"%PYTHON%" -c "import tkinter" >nul 2>&1
if errorlevel 1 (
  echo [REPAIR] tkinter is missing from the local Python runtime.
  if not exist "%REPAIR%" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
      "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $u='https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/REPAIR_PYTHON_RUNTIME.ps1?nocache=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile '%REPAIR%'"
  )
  if not exist "%REPAIR%" (
    echo [ERROR] Python repair helper is unavailable.
    pause
    exit /b 1
  )
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%REPAIR%" -Root "%ROOT%"
  if errorlevel 1 (
    echo [ERROR] Python/tkinter repair failed. See %LOGDIR%
    pause
    exit /b 1
  )
)

if exist "%PYTHON_RUNTIME%" set "PYTHON=%PYTHON_RUNTIME%"

set "CHROME="
if exist "%CONFIG%" (
  for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "try { (Get-Content -Raw '%CONFIG%' | ConvertFrom-Json).chrome_exe } catch {''}"`) do set "CHROME=%%A"
)
if not defined CHROME if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" set "CHROME=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not defined CHROME if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" set "CHROME=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
if not defined CHROME if exist "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe" set "CHROME=%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"

if not defined CHROME (
  echo [ERROR] Official Google Chrome not found.
  pause
  exit /b 1
)
if not exist "%PROFILE%" mkdir "%PROFILE%"

REM Refresh the small modular shell on every Control Center start.
REM If GitHub is temporarily unavailable, a previously cached shell is used.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $u='https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/CONTROL_CENTER_SHELL.py?nocache=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile '%SHELL_ENTRY%'" >nul 2>&1
if errorlevel 1 (
  if exist "%SHELL_ENTRY%" (
    echo [WARN] Could not refresh Modular Shell; using cached shell.py
  ) else (
    echo [WARN] Modular Shell is unavailable; falling back to legacy GUI.
  )
)

if exist "%SHELL_ENTRY%" (
  "%PYTHON%" -m py_compile "%SHELL_ENTRY%" >nul 2>&1
  if errorlevel 1 (
    echo [WARN] shell.py validation failed; falling back to legacy GUI.
    set "ENTRY="
  ) else (
    set "ENTRY=%SHELL_ENTRY%"
  )
)

if not defined ENTRY if exist "%CC_DIR%\gui.py" set "ENTRY=%CC_DIR%\gui.py"
if not defined ENTRY if exist "%CC_DIR%\automation_cli.py" set "ENTRY=%CC_DIR%\automation_cli.py"
if not defined ENTRY if exist "%CC_DIR%\main.py" set "ENTRY=%CC_DIR%\main.py"
if not defined ENTRY if exist "%CC_DIR%\app.py" set "ENTRY=%CC_DIR%\app.py"

if not defined ENTRY (
  echo [ERROR] No Control Center entry script found.
  pause
  exit /b 1
)

echo ============================================================
echo  AutomationPlatform - Modular Control Center
 echo ============================================================
echo  Root   : %ROOT%
echo  Python : %PYTHON%
echo  Chrome : %CHROME%
echo  Profile: %PROFILE%
echo  Entry  : %ENTRY%
echo ============================================================
echo.

set "PYTHONPATH=%ROOT%;%CC_DIR%;%ROOT%\core;%PYTHONPATH%"
set "AUTOMATION_PLATFORM_ROOT=%ROOT%"
set "AUTOMATION_PLATFORM_CONFIG=%CONFIG%"
set "AUTOMATION_PLATFORM_CHROME=%CHROME%"
set "AUTOMATION_PLATFORM_PROFILE=%PROFILE%"
set "AUTOMATION_PLATFORM_PYTHON=%PYTHON%"
set "AUTOMATION_PLATFORM_CDP_URL=http://127.0.0.1:9222"
set "AUTOMATION_PLATFORM_CDP_PORT=9222"

"%PYTHON%" "%ENTRY%"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
  echo.
  echo [ERROR] Exit code %RC% - see %LOGDIR%
  pause
  exit /b %RC%
)
endlocal
exit /b 0
