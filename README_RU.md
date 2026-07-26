# AutomationPlatform v0.6

Локальная платформа: `D:\AutomationPlatform`

Репозиторий: https://github.com/1777maxim7771/AutomationPlatform

## Быстрый старт (чистая машина)

PowerShell:

```powershell
irm https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/INSTALL_AutomationPlatform.ps1 | iex
```

Или скачайте `INSTALL_AutomationPlatform.bat`.

## Что ставится

| Компонент | Примечание |
|-----------|------------|
| **Python full** (`runtime\python`) | С **tkinter** (Tcl/Tk). Embed без GUI не используется |
| **Google Chrome** (системный) | Обязателен. Chrome for Testing **не** используется |
| Профиль | `browser\Chrome_Profile` (CDP :9222) |
| Control Center | `control_center\gui.py` |
| CLI | `automation.cmd` |

## Обновление уже установленной копии

### Способ 1 — рекомендуемый

```cmd
D:\AutomationPlatform\UPDATE_PLATFORM.cmd
```

В окне установщика:

- **Install root:** `D:\AutomationPlatform` (без кавычек)
- Включены: Local Python, Google Chrome, Chrome_Profile, Control Center
- **INSTALL / UPDATE**

Установщик сам:

1. Скачает свежие скрипты с GitHub (с anti-cache)
2. Проверит `tkinter`; при отсутствии переустановит **полный** Python
3. Обновит Control Center и лаунчеры
4. **Не тронет** `browser\Chrome_Profile`, secrets, modules, jobs, logs

### Способ 2 — точечно обновить один файл

```cmd
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri ('https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/START_CONTROL_CENTER.cmd?nocache=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) -OutFile 'D:\AutomationPlatform\START_CONTROL_CENTER.cmd'"
```

Аналогично для `UPDATE_PLATFORM.cmd`, `START_CHROME_DEBUG.cmd`.

### Способ 3 — принудительно обновить core установщика

```cmd
powershell -NoProfile -ExecutionPolicy Bypass -Command "$b='https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/'; $t=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); Invoke-WebRequest -UseBasicParsing -Uri ($b+'INSTALLER_CORE.ps1?nocache='+$t) -OutFile 'D:\AutomationPlatform\installer\INSTALLER_CORE.ps1'; Invoke-WebRequest -UseBasicParsing -Uri ($b+'START_PLATFORM_INSTALLER.ps1?nocache='+$t) -OutFile 'D:\AutomationPlatform\installer\START_PLATFORM_INSTALLER.ps1'; Invoke-WebRequest -UseBasicParsing -Uri ($b+'UPDATE_PLATFORM.cmd?nocache='+$t) -OutFile 'D:\AutomationPlatform\UPDATE_PLATFORM.cmd'"
```

Затем снова `UPDATE_PLATFORM.cmd`.

## Запуск после обновления

```cmd
D:\AutomationPlatform\runtime\python\python.exe -c "import tkinter; print('tkinter OK')"
D:\AutomationPlatform\START_CONTROL_CENTER.cmd
D:\AutomationPlatform\START_CHROME_DEBUG.cmd
```

В окне Control Center должно быть: `[v20260726c]` и `Entry: ...\control_center\gui.py`.

## Только CLI (без GUI)

```cmd
D:\AutomationPlatform\automation.cmd list
D:\AutomationPlatform\automation.cmd run browser.start
```

## Известные исправления в этой ветке

- Путь без кавычек (`"D:\path\"` больше не ломает установку)
- Обязательный официальный Google Chrome
- Лаунчер ищет `gui.py`
- Python full + проверка `tkinter`
- Cache-bust при скачивании с raw.githubusercontent.com
