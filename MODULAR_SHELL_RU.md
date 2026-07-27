# AutomationPlatform Modular Shell

## Цель

AutomationPlatform является единственной главной графической оболочкой. Панели установленных модулей открываются внутри центральной рабочей области того же окна.

```text
AutomationPlatform Control Center
│
├── Главное меню
│   ├── Главная
│   ├── Команды
│   ├── Параметры
│   ├── Conversation Exporter
│   ├── Центр модулей
│   ├── Результаты
│   └── Логи
│
└── Workspace
    └── активная панель
```

## Без закрытия окна

При первом открытии модульная панель создаётся как дочерний `tk.Frame` и сохраняется в кэше Shell.

При переключении меню AutomationPlatform использует:

```python
current_panel.pack_forget()
selected_panel.pack(fill="both", expand=True)
```

Объект панели не уничтожается. Поэтому состояние элементов интерфейса остаётся в памяти, главное окно не закрывается и новое окно AutomationPlatform не создаётся.

## Dynamic Conversation Exporter

Модуль:

```text
https://github.com/1777maxim7771/Dynamic_Conversation_Exporter
```

регистрирует встроенную панель через `module_manifest.json`:

```text
ui.mode = embedded
ui.ui_api = 1
ui.source = embedded_panel.py
ui.entry_class = DynamicConversationExporterPanel
```

После установки Optional Modules Manager скачивает `embedded_panel.py` непосредственно из репозитория модуля и создаёт:

```text
D:\AutomationPlatform\modules\dynamic_conversation_exporter\platform_integration.json
```

Modular Shell сканирует `modules\*\platform_integration.json` и автоматически добавляет совместимые панели в меню `МОДУЛИ`.

## Центр модулей

В Shell есть встроенный `ЦЕНТР МОДУЛЕЙ`. Для Dynamic Conversation Exporter доступны действия:

```text
УСТАНОВИТЬ / ОБНОВИТЬ
ОТКРЫТЬ ПАНЕЛЬ
ПЕРЕСКАНИРОВАТЬ
```

Установка выполняется внутри главной AutomationPlatform через `OPTIONAL_MODULES_MANAGER.ps1`. Отдельное окно установщика для этого модуля не требуется.

## Единый стиль

Embedded-панель получает от AutomationPlatform объект `services`, включая общую тему:

```text
services.theme
services.root
services.python_exe
services.chrome_profile
services.cdp_url
services.run_process(...)
```

Поэтому модуль использует те же цвета, фон и визуальную структуру, что и главная оболочка.

## Общие ресурсы

Dynamic Conversation Exporter использует общие ресурсы платформы:

```text
Python:        <ROOT>\runtime\python\python.exe
ChromeProfile:<ROOT>\browser\Chrome_Profile
CDP:           http://127.0.0.1:9222
```

При запуске фоновых процессов передаются:

```text
AUTOMATION_PLATFORM_ROOT
AUTOMATION_PLATFORM_PYTHON
AUTOMATION_PLATFORM_PROFILE
AUTOMATION_PLATFORM_CDP_URL
AUTOMATION_PLATFORM_CDP_PORT
AUTOMATION_PLATFORM_EMBEDDED=1
```

## Самообновление

`START_CONTROL_CENTER.cmd` при каждом запуске пытается получить свежий `CONTROL_CENTER_SHELL.py` из GitHub. Если GitHub временно недоступен, используется локальная cached-копия Shell. При отсутствии Shell остаётся fallback на legacy `control_center\gui.py`.

Embedded UI модулей синхронизируется менеджером модулей даже тогда, когда сам runtime-пакет модуля уже актуален и получает `SKIP`.
