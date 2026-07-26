# AutomationPlatform Full Starter v0.4.0

Это стартовая архитектура для `D:\AutomationPlatform`.

## Два уровня

### 1. START_PLATFORM_INSTALLER.ps1
Первая графическая панель. Работает на Windows без установленного Python.

Она устанавливает/обновляет:

- локальный Python 3.13.14 x64;
- Chrome for Testing Stable;
- Chrome Debug Profile;
- Control Center.

### 2. AutomationPlatform Control Center
После установки:

`D:\AutomationPlatform\START_CONTROL_CENTER.cmd`

В нём есть:

- Главная;
- динамические команды;
- общие параметры;
- DPAPI-секреты/API keys;
- GitHub-модули;
- обновление модулей;
- результаты/логи;
- CLI/AI command interface.

## GitHub Repository

Создайте Repository:

`AutomationPlatform`

и загрузите содержимое этой папки `GitHub_Repository_Template` в корень репозитория.

После загрузки Raw URL manifest будет:

`https://raw.githubusercontent.com/OWNER/AutomationPlatform/main/platform_manifest.json`

Этот URL вводится в стартовой панели.

## Что хранится локально и не должно заменяться обновлением

- `browser\Chrome_Profile`
- `data\shared_values.json`
- `data\secrets.dpapi.json`
- `jobs`
- `logs`
- пользовательские модули

## Командный интерфейс для AI

```cmd
D:\AutomationPlatform\automation.cmd list
D:\AutomationPlatform\automation.cmd describe browser.start
D:\AutomationPlatform\automation.cmd run browser.start
D:\AutomationPlatform\automation.cmd run example.register --param site_url=https://example.com
```

AI может читать только:

`D:\AutomationPlatform\commands\catalog.json`

и не читать весь исходный код.

## module.json

Каждый модуль публикует свой командный контракт. Control Center автоматически строит GUI-поля из `parameters`.

Для секретов используйте:

`"type": "secret_ref"`

Тогда в каталог и обычные job-файлы попадает только имя секрета, а не его значение.

## Самообновление

Повторный запуск `START_PLATFORM_INSTALLER.ps1` является механизмом обновления платформенного слоя:

- Python можно проверить/доставить;
- Chrome обновляется до текущего Stable CfT;
- Control Center заменяется версией, указанной в `platform_manifest.json`;
- Chrome Profile и локальные данные не удаляются.

Позднее этот же вызов можно сделать одной кнопкой непосредственно из Control Center.
