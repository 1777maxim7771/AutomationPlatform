# AutomationPlatform Full Starter v0.5.0

Центральный репозиторий для развёртывания и обновления локальной платформы в:

`D:\AutomationPlatform`

## Быстрый старт

В PowerShell:

```powershell
irm https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/INSTALL_AutomationPlatform.ps1 | iex
```

Или скачайте и запустите `INSTALL_AutomationPlatform.bat`.

Манифест:

`https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/platform_manifest.json`

## Что устанавливается

| Компонент | Путь | Обязателен |
|-----------|------|------------|
| Локальный Python (embed) | `runtime\python\python.exe` | рекомендуется |
| **Официальный Google Chrome** | системный `chrome.exe` | **да** |
| Debug-профиль | `browser\Chrome_Profile` | да |
| Control Center | `control_center\`, `core\`, `commands\` | да |
| CLI | `automation.cmd` | да |

**Chrome for Testing не используется** (плашка «только для тестирования» недопустима).
Если Google Chrome отсутствует, установщик предлагает поставить официальный Chrome.
Отказ от установки Chrome **прерывает** развёртывание платформы.

## Chrome Debug

```cmd
D:\AutomationPlatform\START_CHROME_DEBUG.cmd
```

Запускает **официальный** Google Chrome с:

- `--remote-debugging-port=9222`
- `--user-data-dir=D:\AutomationPlatform\browser\Chrome_Profile`

Один раз войдите в ChatGPT в этом окне — сессия сохранится в профиле платформы.

## Control Center

```cmd
D:\AutomationPlatform\START_CONTROL_CENTER.cmd
```

Лаунчер **проверяет зависимости** перед стартом:

1. Python (`config\platform.json` → `runtime\python\python.exe`)
2. Официальный Google Chrome
3. Папка `control_center\` и entry-скрипт (`main.py` / `app.py` / …)

Если чего-то нет — окно **не закрывается сразу**, показывает текст ошибки и `pause`.

### Почему Control Center мог «не запускаться»

| Причина | Решение |
|---------|---------|
| Нет `runtime\python\python.exe` | `UPDATE_PLATFORM.cmd`, включить Local Python |
| В `platform.json` битый путь к Python/Chrome | перезапустить UPDATE |
| Пустой/битый `control_center\` | UPDATE с галкой Control Center |
| Двойной клик закрывает окно до чтения ошибки | запускать из `cmd` |

Диагностика:

```cmd
cd /d D:\AutomationPlatform
START_CONTROL_CENTER.cmd
type config\platform.json
dir runtime\python\python.exe
dir control_center
```

## Только команды (без GUI)

Платформа рассчитана и на CLI-only режим:

```cmd
D:\AutomationPlatform\automation.cmd list
D:\AutomationPlatform\automation.cmd describe browser.start
D:\AutomationPlatform\automation.cmd run browser.start
D:\AutomationPlatform\automation.cmd run example.register --param site_url=https://example.com
```

Каталог: `commands\catalog.json`.

## Обновление / ремонт

```cmd
D:\AutomationPlatform\UPDATE_PLATFORM.cmd
```

Повторный запуск **самовосстанавливающий**:

- доставляет отсутствующий Python (embed_first);
- требует/ставит Google Chrome;
- обновляет Control Center и лаунчеры;
- **не трогает** `browser\Chrome_Profile`, secrets, пользовательские modules/jobs/logs.

## Структура после установки

```text
D:\AutomationPlatform\
  START_CONTROL_CENTER.cmd
  START_CHROME_DEBUG.cmd
  UPDATE_PLATFORM.cmd
  automation.cmd
  config\platform.json
  browser\Chrome_Profile\
  runtime\python\
  control_center\
  core\
  commands\
  modules\
  logs\
  installer\
```

## Безопасность

Не коммитьте профили Chrome, API-ключи, токены, `.env`, runtime и пользовательские данные (см. `.gitignore`).
