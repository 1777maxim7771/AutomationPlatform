# AutomationPlatform Embedded Module UI Contract

## Goal

AutomationPlatform owns one desktop window. Installed modules may expose an embedded Tkinter `Frame` that is loaded into the central workspace. Switching modules must not close the main window and must not create another AutomationPlatform window.

## Contract version

```text
platform_api: 1
ui_api: 1
```

## Remote module manifest

A module that supports the central shell declares:

```json
{
  "platform_api": 1,
  "ui": {
    "mode": "embedded",
    "ui_api": 1,
    "source": "embedded_panel.py",
    "installed_file": "embedded_panel.py",
    "entry_class": "DynamicConversationExporterPanel",
    "menu_label": "Conversation Exporter",
    "menu_group": "modules",
    "cache_view": true,
    "single_window": true
  }
}
```

## Python interface

The `entry_class` must accept exactly:

```python
PanelClass(master, services)
```

and must inherit from `tk.Frame` or a compatible Tkinter widget.

It must **not** call:

```python
tk.Tk()
tk.Toplevel()
mainloop()
```

for the embedded view.

AutomationPlatform creates the one root window and passes the workspace as `master`.

## Optional lifecycle hook

A panel may implement:

```python
def on_show(self):
    ...
```

AutomationPlatform calls it whenever the cached panel becomes visible again.

## View lifetime

The main Shell caches created module panels. Switching pages uses `pack_forget()` on the current panel and `pack(fill="both", expand=True)` on the selected panel. The panel object remains alive, so controls, selections and in-memory state are preserved.

## Platform services

The `services` object exposes the shared platform environment:

```text
services.root
services.python_exe
services.chrome_profile
services.cdp_url
services.theme
services.run_process(...)
services.open_folder(...)
services.read_json(...)
services.write_json(...)
services.refresh_modules()
services.show_page(...)
```

Module processes also receive environment variables:

```text
AUTOMATION_PLATFORM_ROOT
AUTOMATION_PLATFORM_PYTHON
AUTOMATION_PLATFORM_PROFILE
AUTOMATION_PLATFORM_CDP_URL
AUTOMATION_PLATFORM_CDP_PORT
AUTOMATION_PLATFORM_EMBEDDED=1
```

## Installation

The Optional Modules Manager downloads the module package and then separately refreshes the small embedded UI source from the module repository. It writes:

```text
<module>\platform_integration.json
```

The Shell scans installed module directories for this file and automatically adds compatible modules to the left navigation menu.

## Standalone compatibility

A module may keep a separate standalone launcher for use outside AutomationPlatform. That launcher is not used to render the embedded page. The embedded page remains a normal child Frame of the AutomationPlatform workspace.
