# Опциональные модули AutomationPlatform

## Dynamic Conversation Exporter

Репозиторий модуля:

```text
https://github.com/1777maxim7771/Dynamic_Conversation_Exporter
```

Версия модуля: `1.5.0`.

### Установка вместе с AutomationPlatform

В актуальном `INSTALLER_UI.ps1` добавлен блок **OPTIONAL MODULE** с флажком:

```text
Dynamic Conversation Exporter v1.5 - ChatGPT / Chrome CDP exporter
```

Если флажок установлен, основной Bootstrap передаёт параметр:

```text
-InstallDynamicConversationExporter
```

и на фазе `PHASE 5/5 - Optional modules` модуль устанавливается в:

```text
D:\AutomationPlatform\modules\dynamic_conversation_exporter
```

Если модуль не выбран и ещё не установлен, выполняется `SKIP_OPTIONAL`.

Если модуль уже установлен, следующие запуски AutomationPlatform автоматически проверяют его версию и целостность. При наличии новой версии выполняется `UPDATE`, при повреждении — `REPAIR`, при актуальном исправном состоянии — `SKIP`.

### Общие ресурсы платформы

Модуль не создаёт отдельный Python runtime. Используется:

```text
D:\AutomationPlatform\runtime\python\python.exe
```

Также используется общий Chrome Debug/CDP AutomationPlatform на порту `9222` и общий постоянный Chrome Profile.

Поскольку этот конкретный модуль предназначен для экспорта разговоров ChatGPT, его собственный launcher может явно открыть:

```text
https://chatgpt.com/
```

Это не меняет глобальное правило AutomationPlatform: сама платформа по-прежнему не имеет ChatGPT как стартовый URL по умолчанию.

### Python-зависимости

Модуль содержит `requirements.txt`. Optional Modules Manager проверяет зависимости через локальный Python платформы и устанавливает их только при необходимости. Хэш `requirements.txt` сохраняется в:

```text
D:\AutomationPlatform\data\module_dependencies.json
```

### Сохранение данных при обновлении

При `UPDATE`/`REPAIR` сохраняются пользовательские данные модуля:

```text
exports
logs
panel_position.json
config.json
```

Перед заменой выполняется резервное перемещение текущего модуля. Если новая версия не проходит проверку, выполняется rollback.

### Проверка пакета

Пакет модуля хранится в отдельном GitHub-репозитории частями Base64. Перед установкой AutomationPlatform:

1. загружает `module_manifest.json`;
2. собирает ZIP из `package_parts`;
3. проверяет SHA-256;
4. распаковывает во временную staging-папку;
5. проверяет обязательные файлы и версию;
6. только после успешной проверки активирует новую версию.

### Запуск после установки

Основной launcher модуля внутри каталога:

```text
D:\AutomationPlatform\modules\dynamic_conversation_exporter\00_START_ALL.cmd
```

Optional Modules Manager также создаёт корневую точку запуска:

```text
D:\AutomationPlatform\START_DYNAMIC_CONVERSATION_EXPORTER.cmd
```

### Диагностика

Журнал Optional Modules Manager:

```text
D:\AutomationPlatform\logs\latest_optional_modules.log
```

Состояние установленных опциональных модулей:

```text
D:\AutomationPlatform\data\optional_modules_status.json
```
