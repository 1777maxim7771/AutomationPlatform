# AutomationPlatform Full Starter v0.4.0

Центральный репозиторий для развёртывания и обновления локальной платформы в:

`D:\AutomationPlatform`

## Быстрый старт — один файл

Для первоначальной установки достаточно скачать:

`START_PLATFORM_INSTALLER.ps1`

Он уже знает основной GitHub Manifest:

`https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/platform_manifest.json`

При запуске стартовая панель сама скачивает актуальный `INSTALLER_CORE.ps1` с этого репозитория и затем разворачивает выбранные компоненты.

## Что устанавливается

- отдельный локальный Python в `D:\AutomationPlatform\runtime\python`;
- Chrome for Testing в `D:\AutomationPlatform\runtime\chrome`;
- постоянный Debug-профиль в `D:\AutomationPlatform\browser\Chrome_Profile`;
- AutomationPlatform Control Center;
- командный интерфейс `automation.cmd` для GUI, CLI, AI-агентов и будущих workflow.

## Chrome Profile

`browser\Chrome_Profile` создаётся только локально. Он не скачивается из GitHub и не заменяется обновлением платформы. В нём сохраняются локальные браузерные сессии и авторизации.

## Control Center

После установки запускается:

`D:\AutomationPlatform\START_CONTROL_CENTER.cmd`

В Control Center предусмотрены:

- состояние Python / Chrome / Chrome Profile / CDP;
- динамический каталог команд;
- общие параметры;
- DPAPI-хранилище секретов/API keys;
- установка и обновление GitHub-модулей;
- результаты и журналы;
- CLI/AI command interface.

## Команды для AI

```cmd
D:\AutomationPlatform\automation.cmd list
D:\AutomationPlatform\automation.cmd describe browser.start
D:\AutomationPlatform\automation.cmd run browser.start
D:\AutomationPlatform\automation.cmd run example.register --param site_url=https://example.com
```

AI может использовать `D:\AutomationPlatform\commands\catalog.json` и командные контракты модулей вместо чтения всего исходного проекта.

## Обновление платформы

Во время первой установки в локальную платформу записываются актуальные файлы установщика и создаётся:

`D:\AutomationPlatform\UPDATE_PLATFORM.cmd`

Повторный запуск обновления может доставить/обновить программный слой, не удаляя пользовательские данные.

Не заменяются:

- `browser\Chrome_Profile`;
- `data\shared_values.json`;
- `data\secrets.dpapi.json`;
- пользовательские `modules`;
- `jobs`;
- `logs`.

## GitHub package

Control Center публикуется как:

`packages/control_center_v0.4.0.part01.b64` … `part06.b64`

На GitHub пакет хранится несколькими Base64-текстовыми частями, затем установщик автоматически объединяет их и локально восстанавливает ZIP. SHA-256 исходного ZIP зафиксирован в `platform_manifest.json` и проверяется до распаковки.

## Безопасность репозитория

Никогда не коммитьте локальные профили Chrome, API-ключи, токены, `.env`, runtime и пользовательские данные. Для этого используется `.gitignore`.
