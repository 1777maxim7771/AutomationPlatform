# AutomationPlatform

Локальный корень: `D:\AutomationPlatform`  
Репозиторий: `1777maxim7771/AutomationPlatform`

## Главная точка входа

Для первой установки, повторной проверки, обновления и ремонта используется один файл:

```text
INSTALL_AutomationPlatform.bat
```

BAT остаётся маленьким bootstrap-файлом и при каждом запуске получает актуальный `BOOTSTRAP_RUNNER.ps1` из GitHub. Поэтому исправления платформы и новая логика подтягиваются без ручного редактирования локального кода.

## Текущая схема

```text
INSTALL_AutomationPlatform.bat
        ↓
latest BOOTSTRAP_RUNNER.ps1
        ↓
latest platform_manifest.json
        ↓
PYTHON_RUNTIME_MANAGER.ps1
        ↓
CHROME_RUNTIME_MANAGER.ps1
        ↓
подготовка пакета Control Center
        ↓
INSTALLER_CORE.ps1
        ↓
финальная Health Check
        ↓
Control Center
```

Здоровые компоненты получают `SKIP`. Отсутствующие компоненты получают `INSTALL`, устаревшие — `UPDATE`, повреждённые — `REPAIR`.

## Python

Python является application-local runtime и находится только здесь:

```text
D:\AutomationPlatform\runtime\python
```

Используется официальный PythonCore runtime ZIP. Проверяются `python.exe`, точная версия Python, `tkinter` и `pip`. Новый runtime сначала проверяется во временной staging-папке и только после успешной проверки активируется.

## Google Chrome

Для Chrome используется отдельный `CHROME_RUNTIME_MANAGER.ps1`.

Политика обновления:

- Chrome отсутствует — установка обязательна;
- Chrome актуален — `SKIP`;
- новая версия доступна, но Chrome сейчас запущен — `DEFER_UPDATE`, рабочий браузер сохраняется;
- обновление MSI завершилось ошибкой, но установленный Chrome продолжает работать — `UPDATE_FAILED_USING_EXISTING`, ошибка записывается как предупреждение и не блокирует установку AutomationPlatform;
- только отсутствие рабочего Chrome после обязательной установки является фатальной ошибкой.

Журнал Chrome:

```text
D:\AutomationPlatform\logs\latest_chrome_runtime.log
```

## Chrome Debug и стартовый сайт

ChatGPT больше не является стартовым сайтом по умолчанию.

Стартовый URL хранится только при явном сохранении пользователем:

```text
data\shared_values.json
browser.start_url
```

Если `browser.start_url` отсутствует:

- Control Center показывает диалог **«Какой сайт открыть?»**;
- `START_CHROME_DEBUG.cmd` запрашивает сайт в консоли, если был запущен напрямую;
- CLI/AI-команда `browser.start` возвращает `needs_input`, а не подставляет ChatGPT автоматически.

Старое историческое значение `https://chatgpt.com/`, если оно было создано прежней версией платформы, удаляется миграцией Control Center v0.5.0.

## Control Center v0.5.0

Основные изменения интерфейса:

- яркая тёмная динамическая тема;
- glow/hover/press эффекты кнопок;
- pulse-эффект для основных действий;
- живые индикаторы Python / Chrome / CDP / Control Center;
- отдельная карточка стартового URL браузера;
- кнопки задать и очистить URL;
- диалог запроса сайта перед запуском Chrome Debug, когда URL не сохранён;
- сохранены вкладки команд, параметров, секретов, модулей и результатов.

## Chrome Profile

Постоянный браузерный профиль:

```text
D:\AutomationPlatform\browser\Chrome_Profile
```

Он не удаляется обычным обновлением платформы. Авторизации, cookies и локальные данные браузера сохраняются.

## Логи

Все журналы находятся здесь:

```text
D:\AutomationPlatform\logs\
```

Главные файлы:

```text
latest_bootstrap.log
latest_python_runtime.log
latest_chrome_runtime.log
install_YYYYMMDD_HHMMSS.log
bootstrap_YYYYMMDD_HHMMSS.log
python_runtime_YYYYMMDD_HHMMSS.log
chrome_runtime_YYYYMMDD_HHMMSS.log
```

Состояние компонентов сохраняется в:

```text
D:\AutomationPlatform\data\platform_status.json
```

## Обновление

Можно повторно запустить тот же `INSTALL_AutomationPlatform.bat` либо:

```cmd
D:\AutomationPlatform\UPDATE_PLATFORM.cmd
```

Пользовательские данные, которые сохраняются при обновлении:

```text
browser\Chrome_Profile
data\shared_values.json
data\secrets.dpapi.json
modules
jobs
logs
```
