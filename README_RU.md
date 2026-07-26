# AutomationPlatform

Локальный корень: `D:\AutomationPlatform`  
Репозиторий: `1777maxim7771/AutomationPlatform`

## Главный принцип

Основная точка входа теперь одна:

```text
INSTALL_AutomationPlatform.bat
```

Один и тот же BAT используется для:

- первой установки;
- повторной проверки;
- обновления;
- ремонта повреждённых компонентов.

BAT не содержит основную логику платформы. При каждом запуске он автоматически скачивает актуальный:

```text
BOOTSTRAP_RUNNER.ps1
```

Runner получает свежие:

```text
platform_manifest.json
INSTALLER_CORE.ps1
```

Поэтому дальнейшие исправления и новая логика подтягиваются из GitHub автоматически без ручного редактирования BAT.

## Что происходит при каждом запуске

```text
INSTALL_AutomationPlatform.bat
        ↓
latest BOOTSTRAP_RUNNER.ps1
        ↓
latest platform_manifest.json
        ↓
latest INSTALLER_CORE.ps1
        ↓
проверка фактического состояния
        ↓
SKIP / INSTALL / UPDATE / REPAIR
        ↓
финальная Health Check
        ↓
Control Center
```

### Python

Проверяются:

- наличие `D:\AutomationPlatform\runtime\python\python.exe`;
- версия Python;
- обязательный `import tkinter`.

Если версия правильная и `tkinter` работает — Python **не переустанавливается**.

Если Python отсутствует — `INSTALL`.

Если версия отличается от Manifest — `UPDATE`.

Если Python есть, но `tkinter` отсутствует — `REPAIR`: локальный runtime удаляется и устанавливается полный CPython с Tcl/Tk.

При `require_tkinter=true` embedded Python больше не используется как fallback.

### Google Chrome

Проверяются:

- наличие официального Google Chrome;
- установленная версия;
- актуальная Stable-версия из Google version endpoint.

Если Chrome отсутствует — установка.

Если установленная версия старее известной Stable — обновление.

Если Chrome актуален — `SKIP`.

### Chrome Profile

```text
D:\AutomationPlatform\browser\Chrome_Profile
```

никогда не удаляется при обычном обновлении. Если папка уже существует — `SKIP / PRESERVE`.

### Control Center

Сравниваются:

- версия в `config\platform.json`;
- версия в `platform_manifest.json`;
- наличие обязательных файлов `control_center\gui.py` и `core\router.py`.

Если версия и файлы правильные — пакет не распаковывается повторно.

Если версия изменилась — `UPDATE`.

Если файлы отсутствуют/повреждены — `INSTALL_REPAIR`.

После проверки программного пакета launcher-скрипты всегда загружаются непосредственно с GitHub. Поэтому старая копия launcher внутри ZIP не может откатить новое исправление.

## Логи и диагностика

Все журналы находятся здесь:

```text
D:\AutomationPlatform\logs\
```

Основные файлы:

```text
bootstrap_YYYYMMDD_HHMMSS.log
install_YYYYMMDD_HHMMSS.log
latest_bootstrap.log
```

Файл текущего состояния:

```text
D:\AutomationPlatform\data\platform_status.json
```

Он содержит фактическое состояние компонентов, версии и последнее действие: `SKIP`, `INSTALL`, `UPDATE`, `REPAIR`.

При ошибке сначала смотрите:

```text
D:\AutomationPlatform\logs\latest_bootstrap.log
```

и самый новый:

```text
D:\AutomationPlatform\logs\install_*.log
```

## Основные файлы GitHub

| Файл | Назначение |
|---|---|
| `INSTALL_AutomationPlatform.bat` | единый старт Install / Update / Repair |
| `BOOTSTRAP_RUNNER.ps1` | всегда свежий bootstrap, загружаемый BAT |
| `INSTALLER_CORE.ps1` | идемпотентная проверка и установка компонентов |
| `platform_manifest.json` | версии и правила обновления |
| `START_CONTROL_CENTER.cmd` | запуск Control Center |
| `START_CHROME_DEBUG.cmd` | запуск Chrome Debug / CDP |
| `UPDATE_PLATFORM.cmd` | локальный ярлык на тот же универсальный механизм |
| `REPAIR_PYTHON_RUNTIME.ps1` | аварийный специализированный ремонт Python |

## Первый запуск

Скачайте из GitHub только:

```text
INSTALL_AutomationPlatform.bat
```

и запустите его.

По умолчанию платформа устанавливается в:

```text
D:\AutomationPlatform
```

## Повторный запуск

Можно снова запустить тот же BAT. Здоровые и актуальные компоненты будут пропущены автоматически.

Также после установки доступен:

```cmd
D:\AutomationPlatform\UPDATE_PLATFORM.cmd
```

## Пользовательские данные, которые сохраняются

При обновлении не удаляются:

```text
browser\Chrome_Profile
data\shared_values.json
data\secrets.dpapi.json
modules
jobs
logs
```
