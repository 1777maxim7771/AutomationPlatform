# AutomationPlatform

Локальный корень: `D:\AutomationPlatform`  
Репозиторий: `1777maxim7771/AutomationPlatform`

## Главная точка входа

Для первой установки, повторной проверки, обновления и ремонта используется один файл:

```text
INSTALL_AutomationPlatform.bat
```

BAT остаётся маленьким стабильным bootstrap-файлом. При каждом запуске он получает из GitHub **актуальный `INSTALLER_UI.ps1`**, а интерфейс уже получает актуальный `BOOTSTRAP_RUNNER.ps1`. Поэтому дизайн панели, логика установки и обновления могут меняться в репозитории без ручного редактирования локального BAT.

## Текущая схема

```text
INSTALL_AutomationPlatform.bat
        ↓
latest INSTALLER_UI.ps1
        ↓
latest BOOTSTRAP_RUNNER.ps1
        ↓
latest platform_manifest.json
        ↓
PYTHON_RUNTIME_MANAGER.ps1
        ↓
CHROME_RUNTIME_MANAGER.ps1
        ↓
Control Center package/cache
        ↓
PLATFORM_FINALIZER.ps1
        ↓
Control Center compatibility validation
        ↓
config / status / launchers / health check
        ↓
Control Center
```

`INSTALLER_CORE.ps1` сохранён только как legacy-совместимость и больше не является основным путём установки. Python и Chrome не проверяются второй раз старым Core.

Здоровые компоненты получают `SKIP`. Отсутствующие компоненты получают `INSTALL`, устаревшие — `UPDATE`, повреждённые — `REPAIR`.

## Лёгкий динамический Installer UI

`INSTALLER_UI.ps1` использует только штатные Windows WinForms/System.Drawing и не требует отдельного UI-фреймворка.

Интерфейс содержит:

- объёмные кнопки с тенью;
- hover glow;
- видимый press/down эффект;
- мягкий pulse-эффект основной кнопки;
- отдельные карточки `PYTHON RUNTIME`, `GOOGLE CHROME`, `CONTROL CENTER`;
- цветовые состояния OK / WARNING / ERROR;
- живую полосу прогресса по 4 фазам;
- живое чтение `logs\latest_bootstrap.log` примерно каждые 300 мс;
- установку в отдельном скрытом процессе, поэтому окно остаётся отзывчивым и не зависает.

## Python

Python является application-local runtime и находится только здесь:

```text
D:\AutomationPlatform\runtime\python
```

Используется официальный PythonCore runtime ZIP. Проверяются `python.exe`, точная версия Python, `tkinter` и `pip`.

Если текущий runtime исправен, выполняется `SKIP` и Python вообще не скачивается повторно. Если требуется установка/ремонт, уже скачанный ZIP повторно используется при совпадении SHA-256.

## Google Chrome

Для Chrome используется только `CHROME_RUNTIME_MANAGER.ps1`.

Политика обновления:

- Chrome отсутствует — установка обязательна;
- Chrome исправен — используется существующий браузер;
- новая версия доступна, но Chrome сейчас запущен — `DEFER_UPDATE`;
- обновление MSI завершилось ошибкой, но установленный Chrome продолжает работать — `UPDATE_FAILED_USING_EXISTING`, платформа продолжает работу;
- только отсутствие рабочего Chrome является фатальной ошибкой.

Старый `INSTALLER_CORE.ps1` больше не повторяет Chrome version-policy после Chrome Manager.

## Control Center package/cache

Bootstrap сначала проверяет уже собранный:

```text
D:\AutomationPlatform\_bootstrap\downloads\ControlCenter-<version>.zip
```

Если SHA-256 совпадает с Manifest, части пакета с GitHub повторно не скачиваются. При смене версии Bootstrap также умеет переиспользовать другой уже имеющийся `ControlCenter-*.zip`, если его SHA-256 полностью совпадает.

## Control Center v0.5.1

Версия `0.5.1` содержит hotfix кастомного `FXButton`.

В предыдущей сборке визуальный класс использовал `self._w` как поле ширины кнопки. В Tkinter `_w` зарезервировано для Tcl widget path. Например, кнопка шириной `195` перезаписывала служебное значение на `"195"`, после чего операции Canvas завершались ошибкой:

```text
_tkinter.TclError: invalid command name "195"
```

`PLATFORM_FINALIZER.ps1` теперь:

- находит именно блок класса `FXButton`;
- заменяет конфликтующее пользовательское поле `_w` на `_fx_w`;
- отдельно заменяет `_h` на `_fx_h`, если оно используется как поле высоты;
- проверяет, что `self._w = width` больше не осталось;
- выполняет `python -m py_compile control_center\gui.py`;
- записывает результат patch/validation в журнал и `platform_status.json`.

Hotfix запускается даже при `SKIP`, поэтому ранее установленная повреждённая копия GUI может быть исправлена следующим самообновлением.

Остальные возможности Control Center:

- яркая тёмная динамическая тема;
- glow/hover/press эффекты кнопок;
- pulse-эффект основных действий;
- живые индикаторы Python / Chrome / CDP / Control Center;
- отдельная карточка стартового URL браузера;
- запрос сайта, когда URL не сохранён;
- вкладки команд, параметров, секретов, модулей и результатов.

## Chrome Debug и стартовый сайт

ChatGPT не является стартовым сайтом по умолчанию.

Стартовый URL хранится только при явном сохранении пользователем:

```text
data\shared_values.json
browser.start_url
```

Если `browser.start_url` отсутствует, Control Center или `START_CHROME_DEBUG.cmd` спрашивает, какой сайт открыть.

## Chrome Profile

Постоянный браузерный профиль:

```text
D:\AutomationPlatform\browser\Chrome_Profile
```

Он не удаляется обычным обновлением платформы. Авторизации, cookies и локальные данные браузера сохраняются.

## Логи

```text
D:\AutomationPlatform\logs\
```

Основные журналы:

```text
latest_bootstrap.log
latest_python_runtime.log
latest_chrome_runtime.log
latest_finalizer.log
bootstrap_YYYYMMDD_HHMMSS.log
python_runtime_YYYYMMDD_HHMMSS.log
chrome_runtime_YYYYMMDD_HHMMSS.log
finalizer_YYYYMMDD_HHMMSS.log
```

Состояние компонентов:

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
