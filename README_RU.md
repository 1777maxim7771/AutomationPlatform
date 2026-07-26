# AutomationPlatform

Локальный корень: `D:\AutomationPlatform`  
Репозиторий: `1777maxim7771/AutomationPlatform`

## Главный принцип

Основная точка входа одна:

```text
INSTALL_AutomationPlatform.bat
```

Один BAT используется для первой установки, повторной проверки, обновления и ремонта. Сам BAT остаётся маленьким bootstrap-файлом и при каждом запуске получает актуальную логику из GitHub.

## Актуальная цепочка

```text
INSTALL_AutomationPlatform.bat
        ↓
latest BOOTSTRAP_RUNNER.ps1
        ↓
latest platform_manifest.json
        ↓
latest PYTHON_RUNTIME_MANAGER.ps1
        ↓
application-local Python health / install / update / repair
        ↓
latest INSTALLER_CORE.ps1
        ↓
Chrome / Profile / Control Center / Launchers
        ↓
final Health Check
        ↓
Control Center
```

Здоровые компоненты получают `SKIP`. Отсутствующие — `INSTALL`, устаревшие — `UPDATE`, повреждённые — `REPAIR`.

## Python — только внутри AutomationPlatform

Python находится здесь:

```text
D:\AutomationPlatform\runtime\python
```

Для Python больше не используется обычная установка `python-*.exe` в качестве основного метода. Причина: Windows installer является зарегистрированным продуктом и при наличии той же версии Python в Windows может завершиться кодом `0`, не создав вторую копию в заданном `TargetDir`.

Теперь используется официальный **PythonCore runtime ZIP**, предназначенный Python Install Manager для target/extracted runtimes:

```text
https://www.python.org/ftp/python/3.13.14/python-3.13.14-amd64.zip
```

SHA-256 пакета хранится в `platform_manifest.json`.

`PYTHON_RUNTIME_MANAGER.ps1` выполняет:

1. проверку существующего `runtime\python\python.exe`;
2. проверку версии;
3. проверку `import tkinter`;
4. проверку `python -m pip --version`;
5. `SKIP`, если всё исправно;
6. загрузку runtime ZIP только при необходимости;
7. проверку SHA-256;
8. распаковку сначала в staging-папку;
9. полную проверку staging-runtime **до замены** рабочего Python;
10. только после успешной проверки замену `runtime\python`;
11. финальную проверку и rollback при неудаче.

Этот способ не добавляет Python в `PATH`, не создаёт Start Menu shortcut и не регистрирует отдельную Python installation в Windows.

### Логи Python

```text
D:\AutomationPlatform\logs\python_runtime_YYYYMMDD_HHMMSS.log
D:\AutomationPlatform\logs\latest_python_runtime.log
```

При неудачной staging-проверке лог дополнительно показывает наличие:

```text
python.exe
pythonw.exe
Lib\tkinter\__init__.py
DLLs\_tkinter.pyd
tcl
```

## Google Chrome

Проверяются наличие официального Google Chrome, установленная версия и известная Stable-версия. Если Chrome уже подходит — `SKIP`. Если отсутствует — `INSTALL`; если устарел — `UPDATE`.

## Chrome Profile

```text
D:\AutomationPlatform\browser\Chrome_Profile
```

Профиль не удаляется при обычном обновлении. Если он существует — `SKIP / PRESERVE`.

## Control Center

Сравниваются версия в `config\platform.json`, версия в `platform_manifest.json` и наличие обязательных файлов:

```text
control_center\gui.py
core\router.py
```

Если всё актуально — `SKIP`. При новой версии — `UPDATE`. При повреждении файлов — `INSTALL_REPAIR`.

После установки launchers всегда обновляются непосредственно из GitHub, поэтому старая копия launcher внутри ZIP не должна откатывать исправления.

## Логи и диагностика

Все журналы:

```text
D:\AutomationPlatform\logs\
```

Основные:

```text
bootstrap_YYYYMMDD_HHMMSS.log
latest_bootstrap.log
python_runtime_YYYYMMDD_HHMMSS.log
latest_python_runtime.log
install_YYYYMMDD_HHMMSS.log
```

Состояние платформы:

```text
D:\AutomationPlatform\data\platform_status.json
```

## Основные файлы GitHub

| Файл | Назначение |
|---|---|
| `INSTALL_AutomationPlatform.bat` | единый старт Install / Update / Repair |
| `BOOTSTRAP_RUNNER.ps1` | получает свежую логику и управляет последовательностью |
| `PYTHON_RUNTIME_MANAGER.ps1` | независимый application-local Python runtime |
| `INSTALLER_CORE.ps1` | Chrome / Profile / Control Center / launchers / Health Check |
| `platform_manifest.json` | версии, URL, hashes и правила |
| `START_CONTROL_CENTER.cmd` | запуск Control Center |
| `START_CHROME_DEBUG.cmd` | запуск Chrome Debug / CDP |
| `UPDATE_PLATFORM.cmd` | повторный запуск того же механизма |
| `REPAIR_PYTHON_RUNTIME.ps1` | ручной аварийный вызов Python Runtime Manager |

## Первый запуск

Скачайте только:

```text
INSTALL_AutomationPlatform.bat
```

и запустите. По умолчанию:

```text
D:\AutomationPlatform
```

## Повторный запуск

Можно снова запустить тот же BAT или:

```cmd
D:\AutomationPlatform\UPDATE_PLATFORM.cmd
```

BAT каждый раз получает новую bootstrap-логику с GitHub, поэтому исправления установщика не требуют ручного редактирования локального кода.

## Пользовательские данные, которые сохраняются

```text
browser\Chrome_Profile
data\shared_values.json
data\secrets.dpapi.json
modules
jobs
logs
```
