@echo off
REM AutomationPlatform START_CONTROL_CENTER.cmd v20260726d
setlocal EnableExtensions
cd /d "%~dp0"

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "PROFILE=%ROOT%\browser\Chrome_Profile"
set "CONFIG=%ROOT%\config\platform.json"
set "CC_DIR=%ROOT%\control_center"
set "LOGDIR=%ROOT%\logs"
set "INSTALLERDIR=%ROOT%\installer"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
if not exist "%INSTALLERDIR%" mkdir "%INSTALLERDIR%"

echo ============================================================
echo  AutomationPlatform - Control Center  [v20260726d]
echo ============================================================
echo  Root: %ROOT%
echo.

set "PYTHON="
if exist "%CONFIG%" (
  for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "try { (Get-Content -Raw '%CONFIG%' | ConvertFrom-Json).python_exe } catch {''}"`) do set "PYTHON=%%A"
)
if not defined PYTHON if exist "%ROOT%\runtime\python\python.exe" set "PYTHON=%ROOT%\runtime\python\python.exe"

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

echo  Python : %PYTHON%
"%PYTHON%" --version 2>nul

REM -----------------------------------------------------------------
REM Control Center GUI requires tkinter. Old/embed Python builds may
REM contain python.exe but not Tcl/Tk. Repair the project-local runtime
REM automatically before gui.py is started.
REM -----------------------------------------------------------------
"%PYTHON%" -c "import tkinter" >nul 2>&1
if errorlevel 1 (
  echo.
  echo [REPAIR] tkinter is missing from the local Python runtime.
  echo [REPAIR] Downloading the latest repair script from GitHub...

  set "REPAIR=%INSTALLERDIR%\REPAIR_PYTHON_RUNTIME.ps1"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='Stop'; "^
    "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; "^
    "$u='https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/REPAIR_PYTHON_RUNTIME.ps1?nocache=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); "^
    "Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile '%REPAIR%'"

  if errorlevel 1 (
    echo [ERROR] Could not download Python repair script from GitHub.
    echo         Check internet access and try UPDATE_PLATFORM.cmd
    pause
    exit /b 1
  )

  echo [REPAIR] Reinstalling project-local Python with Tcl/Tk...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%REPAIR%" -Root "%ROOT%"
  if errorlevel 1 (
    echo [ERROR] Automatic Python/tkinter repair failed.
    echo         See: %LOGDIR%
    pause
    exit /b 1
  )

  set "PYTHON=%ROOT%\runtime\python\python.exe"
  "%PYTHON%" -c "import tkinter" >nul 2>&1
  if errorlevel 1 (
    echo [ERROR] tkinter is still unavailable after repair.
    echo         See: %LOGDIR%
    pause
    exit /b 1
  )

  echo [OK] tkinter repaired successfully.
  echo.
)

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
echo  Chrome : %CHROME%
if not exist "%PROFILE%" mkdir "%PROFILE%"
echo  Profile: %PROFILE%

if not exist "%CC_DIR%" (
  echo [ERROR] Missing folder: control_center
  pause
  exit /b 1
)

set "ENTRY=%CC_DIR%\gui.py"
if not exist "%ENTRY%" set "ENTRY=%CC_DIR%\automation_cli.py"
if not exist "%ENTRY%" set "ENTRY=%CC_DIR%\main.py"
if not exist "%ENTRY%" set "ENTRY=%CC_DIR%\app.py"

if not exist "%ENTRY%" (
  echo [ERROR] No entry script in control_center
  echo Expected: gui.py
  dir /b "%CC_DIR%" 2>nul
  pause
  exit /b 1
)

echo  Entry  : %ENTRY%
echo ============================================================
echo.

set "PYTHONPATH=%ROOT%;%CC_DIR%;%ROOT%\core;%PYTHONPATH%"
set "AUTOMATION_PLATFORM_ROOT=%ROOT%"
set "AUTOMATION_PLATFORM_CONFIG=%CONFIG%"
set "AUTOMATION_PLATFORM_CHROME=%CHROME%"
set "AUTOMATION_PLATFORM_PROFILE=%PROFILE%"

"%PYTHON%" "%ENTRY%"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
  echo.
  echo [ERROR] Exit code %RC%  - see %LOGDIR%
  pause
  exit /b %RC%
)
endlocal
exit /b 0
