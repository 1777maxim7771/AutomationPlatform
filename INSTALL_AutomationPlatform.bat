@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
title AutomationPlatform — Bootstrap Installer
color 0B

set "TARGET_ROOT=D:\AutomationPlatform"
set "REPO_RAW=https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main"
set "MANIFEST_URL=%REPO_RAW%/platform_manifest.json"
set "TEMP_BOOT=%TEMP%\AutomationPlatform_Bootstrap"

echo.
echo ============================================================
echo   AutomationPlatform — установка с GitHub
echo ============================================================
echo.
echo   Цель установки : %TARGET_ROOT%
echo   Репозиторий    : github.com/1777maxim7771/AutomationPlatform
echo.
echo ------------------------------------------------------------
echo   Что будет сделано:
echo   1. Создана папка %TARGET_ROOT%
echo   2. Скачаны скрипты установщика с GitHub
echo   3. Установлены / обновлены:
echo        - локальный Python runtime
echo        - Chrome for Testing (debug)
echo        - Control Center
echo        - профиль Chrome_Profile
echo   4. Показаны дальнейшие шаги
echo ------------------------------------------------------------
echo.

where powershell >nul 2>nul
if errorlevel 1 (
    echo [ОШИБКА] PowerShell не найден. Установите Windows PowerShell и повторите.
    pause
    exit /b 1
)

echo [1/4] Подготовка временной папки...
if exist "%TEMP_BOOT%" rmdir /s /q "%TEMP_BOOT%" 2>nul
mkdir "%TEMP_BOOT%" 2>nul
if not exist "%TEMP_BOOT%" (
    echo [ОШИБКА] Не удалось создать %TEMP_BOOT%
    pause
    exit /b 2
)

echo [2/4] Скачиваю START_PLATFORM_INSTALLER.ps1 с GitHub...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; ^
   Invoke-WebRequest -UseBasicParsing -Uri '%REPO_RAW%/START_PLATFORM_INSTALLER.ps1' -OutFile '%TEMP_BOOT%\START_PLATFORM_INSTALLER.ps1'"
if errorlevel 1 (
    echo [ОШИБКА] Не удалось скачать START_PLATFORM_INSTALLER.ps1
    echo Проверьте интернет и доступ к GitHub.
    pause
    exit /b 3
)
if not exist "%TEMP_BOOT%\START_PLATFORM_INSTALLER.ps1" (
    echo [ОШИБКА] Файл установщика не появился после загрузки.
    pause
    exit /b 3
)

echo [3/4] Запускаю установщик...
echo       Корневая папка: %TARGET_ROOT%
echo       Manifest     : %MANIFEST_URL%
echo.
echo   Откроется окно установщика.
echo   Нажмите кнопку «УСТАНОВИТЬ / ОБНОВИТЬ».
echo   В консоли будет виден ход скачивания и распаковки.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TEMP_BOOT%\START_PLATFORM_INSTALLER.ps1" -DefaultRoot "%TARGET_ROOT%" -ManifestUrl "%MANIFEST_URL%"
set "RC=%ERRORLEVEL%"

echo.
echo [4/4] Результат
echo ------------------------------------------------------------
if not "%RC%"=="0" (
    echo [ОШИБКА] Установщик завершился с кодом %RC%.
    echo Смотрите сообщения выше / в окне PowerShell.
    pause
    exit /b %RC%
)

echo [OK] Установка / обновление завершены.
echo.
echo ============================================================
echo   ДАЛЬНЕЙШИЕ ДЕЙСТВИЯ
echo ============================================================
echo.
echo   1. Откройте папку:
echo        %TARGET_ROOT%
echo.
echo   2. Для запуска Control Center используйте:
echo        %TARGET_ROOT%\START_CONTROL_CENTER.cmd
echo.
echo   3. Для повторного обновления платформы:
echo        %TARGET_ROOT%\UPDATE_PLATFORM.cmd
echo      или снова этот bootstrap-файл.
echo.
echo   4. Chrome Debug-порт по умолчанию: 9222
echo      Профиль: %TARGET_ROOT%\browser\Chrome_Profile
echo.
echo   5. Логи и данные:
echo        %TARGET_ROOT%\logs
echo        %TARGET_ROOT%\data
echo.
echo ============================================================
echo.

if exist "%TARGET_ROOT%\START_CONTROL_CENTER.cmd" (
    choice /C YN /M "Открыть Control Center сейчас"
    if not errorlevel 2 (
        start "" "%TARGET_ROOT%\START_CONTROL_CENTER.cmd"
    )
) else (
    echo [INFO] START_CONTROL_CENTER.cmd пока не найден.
    echo        Возможно, в окне установщика не была отмечена
    echo        опция Control Center — запустите установку ещё раз.
)

echo.
pause
endlocal
exit /b 0
