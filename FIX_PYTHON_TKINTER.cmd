@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "PYDIR=%ROOT%\runtime\python"
set "DL=%ROOT%\_bootstrap\downloads"
set "VER=3.13.14"
set "URL=https://www.python.org/ftp/python/%VER%/python-%VER%-amd64.exe"
set "EXE=%DL%\python-%VER%-amd64.exe"

echo ============================================================
echo  Fix Python: install FULL build with tkinter
echo ============================================================
echo  Root : %ROOT%
echo  Dest : %PYDIR%
echo.

if not exist "%DL%" mkdir "%DL%"

if not exist "%EXE%" (
  echo [1/4] Downloading Python %VER% full installer...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri '%URL%' -OutFile '%EXE%'"
  if errorlevel 1 (
    echo [ERROR] Download failed.
    pause
    exit /b 1
  )
) else (
  echo [1/4] Reusing installer: %EXE%
)

echo [2/4] Removing embed Python (no tkinter)...
if exist "%PYDIR%" (
  rmdir /s /q "%PYDIR%" 2>nul
  if exist "%PYDIR%" (
    echo [WARN] Could not fully delete %PYDIR% - close any python.exe and retry
    pause
    exit /b 1
  )
)

echo [3/4] Installing full Python with Tcl/Tk (silent)...
"%EXE%" /quiet InstallAllUsers=0 TargetDir="%PYDIR%" PrependPath=0 AppendPath=0 Include_launcher=0 InstallLauncherAllUsers=0 Include_test=0 Include_doc=0 Shortcuts=0 AssociateFiles=0 Include_pip=1 Include_tcltk=1 Include_tools=1
if errorlevel 1 (
  echo [ERROR] Python installer failed.
  pause
  exit /b 1
)

if not exist "%PYDIR%\python.exe" (
  echo [ERROR] python.exe not found after install.
  pause
  exit /b 1
)

echo [4/4] Verifying tkinter...
"%PYDIR%\python.exe" -c "import tkinter; print('tkinter OK')"
if errorlevel 1 (
  echo [ERROR] tkinter still missing after full install.
  pause
  exit /b 1
)

echo.
echo ============================================================
echo  SUCCESS. Now run:  START_CONTROL_CENTER.cmd
echo ============================================================
pause
endlocal
exit /b 0
