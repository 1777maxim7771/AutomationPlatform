# AutomationPlatform

Локальный корень: `D:\AutomationPlatform`  
Репозиторий: https://github.com/1777maxim7771/AutomationPlatform

## Основные файлы в репозитории

| Файл | Роль |
|------|------|
| `INSTALL_AutomationPlatform.bat` / `.ps1` | Первая установка |
| `UPDATE_PLATFORM.cmd` | Обновление: тянет скрипты с GitHub и ставит/чинит всё |
| `START_PLATFORM_INSTALLER.ps1` | GUI установщика |
| `INSTALLER_CORE.ps1` | Логика установки (Python+tkinter, Chrome, Control Center) |
| `REPAIR_PYTHON_RUNTIME.ps1` | Автоматический ремонт локального Python, если отсутствует `tkinter` |
| `platform_manifest.json` | Версии и настройки |
| `START_CONTROL_CENTER.cmd` | Запуск GUI (`control_center\gui.py`) + проверка/саморемонт `tkinter` |
| `START_CHROME_DEBUG.cmd` | Chrome с CDP :9222 |
| `packages/AutomationPlatform_ControlCenter_v0.4.0.zip` | Пакет Control Center |

## Первая установка

```powershell
irm https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/INSTALL_AutomationPlatform.ps1 | iex
```

## Обновление

```cmd
D:\AutomationPlatform\UPDATE_PLATFORM.cmd
```

Перед запуском GUI updater сам скачивает актуальные `START_PLATFORM_INSTALLER.ps1` и `INSTALLER_CORE.ps1` с GitHub.  
При нажатии **INSTALL / UPDATE** снова берётся свежий Core и:

- ставит/чинит **полный Python с tkinter**, если его нет;
- проверяет **официальный Google Chrome**;
- обновляет Control Center и лаунчеры;
- не трогает `browser\Chrome_Profile`, secrets, modules, jobs, logs.

## Саморемонт tkinter при запуске Control Center

`START_CONTROL_CENTER.cmd` сначала выполняет проверку:

```cmd
python.exe -c "import tkinter"
```

Если локальный Python существует, но `tkinter` отсутствует, лаунчер автоматически скачивает актуальный `REPAIR_PYTHON_RUNTIME.ps1`. Repair-скрипт получает свежий `INSTALLER_CORE.ps1` и переустанавливает **только проектный Python runtime** как полный CPython с Tcl/Tk. После ремонта `tkinter` проверяется повторно и только затем запускается `control_center\gui.py`.

Если локальный `UPDATE_PLATFORM.cmd` ещё старый, один раз:

```cmd
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri ('https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/UPDATE_PLATFORM.cmd?nocache=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) -OutFile 'D:\AutomationPlatform\UPDATE_PLATFORM.cmd'"
```

## Запуск

```cmd
D:\AutomationPlatform\START_CONTROL_CENTER.cmd
D:\AutomationPlatform\START_CHROME_DEBUG.cmd
D:\AutomationPlatform\automation.cmd list
```
