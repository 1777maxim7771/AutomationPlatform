from __future__ import annotations

import importlib.util
import json
import os
import socket
import subprocess
import threading
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, simpledialog, ttk
from typing import Any, Callable

SHELL_VERSION = "0.1.0"
MODULE_UI_API = 1

THEME = {
    "bg": "#08111b",
    "panel": "#0d1a28",
    "panel2": "#102235",
    "card": "#13283a",
    "line": "#24445d",
    "text": "#edf8ff",
    "muted": "#8eabbc",
    "accent": "#38dfb5",
    "accent2": "#44aeea",
    "warning": "#ffbf55",
    "danger": "#ff666d",
    "ok": "#4ce4a9",
}


def _platform_root() -> Path:
    env = os.environ.get("AUTOMATION_PLATFORM_ROOT", "").strip()
    if env:
        return Path(env).resolve()
    here = Path(__file__).resolve()
    return here.parent.parent


class PlatformServices:
    """Small stable service surface passed into embedded module panels."""

    def __init__(self, app: "AutomationShell") -> None:
        self.app = app
        self.root = app.platform_root
        self.theme = THEME
        self.ui_api = MODULE_UI_API

    @property
    def python_exe(self) -> Path:
        return self.root / "runtime" / "python" / "python.exe"

    @property
    def chrome_profile(self) -> Path:
        return self.root / "browser" / "Chrome_Profile"

    @property
    def cdp_url(self) -> str:
        return "http://127.0.0.1:9222"

    def open_folder(self, path: str | Path) -> None:
        p = Path(path)
        p.mkdir(parents=True, exist_ok=True)
        os.startfile(str(p))

    def read_json(self, path: str | Path, default: Any = None) -> Any:
        try:
            return json.loads(Path(path).read_text(encoding="utf-8-sig"))
        except Exception:
            return default

    def write_json(self, path: str | Path, value: Any) -> None:
        p = Path(path)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")

    def run_process(
        self,
        command: list[str] | str,
        *,
        cwd: str | Path | None = None,
        env: dict[str, str] | None = None,
        on_output: Callable[[str], None] | None = None,
        on_done: Callable[[int, str], None] | None = None,
        shell: bool = False,
    ) -> None:
        merged = os.environ.copy()
        merged.update(
            {
                "AUTOMATION_PLATFORM_ROOT": str(self.root),
                "AUTOMATION_PLATFORM_PYTHON": str(self.python_exe),
                "AUTOMATION_PLATFORM_PROFILE": str(self.chrome_profile),
                "AUTOMATION_PLATFORM_CDP_URL": self.cdp_url,
                "AUTOMATION_PLATFORM_CDP_PORT": "9222",
                "AUTOMATION_PLATFORM_EMBEDDED": "1",
            }
        )
        if env:
            merged.update({str(k): str(v) for k, v in env.items()})

        def worker() -> None:
            lines: list[str] = []
            try:
                startup = None
                creationflags = 0
                if os.name == "nt":
                    startup = subprocess.STARTUPINFO()
                    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
                    creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
                proc = subprocess.Popen(
                    command,
                    cwd=str(cwd or self.root),
                    env=merged,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    shell=shell,
                    startupinfo=startup,
                    creationflags=creationflags,
                )
                assert proc.stdout is not None
                for raw in proc.stdout:
                    text = raw.rstrip("\r\n")
                    lines.append(text)
                    if on_output:
                        self.app.after(0, on_output, text)
                rc = proc.wait()
            except Exception as exc:  # pragma: no cover - runtime guard
                rc = 1
                lines.append(f"ERROR: {exc}")
            if on_done:
                self.app.after(0, on_done, rc, "\n".join(lines))

        threading.Thread(target=worker, daemon=True).start()

    def refresh_modules(self) -> None:
        self.app.discover_modules(rebuild_menu=True)

    def show_page(self, page_id: str) -> None:
        self.app.show_page(page_id)


class NavButton(tk.Button):
    def __init__(self, master: tk.Misc, text: str, command: Callable[[], None]) -> None:
        super().__init__(
            master,
            text=text,
            command=command,
            anchor="w",
            padx=18,
            pady=10,
            bd=0,
            relief="flat",
            bg=THEME["panel"],
            fg=THEME["text"],
            activebackground=THEME["panel2"],
            activeforeground=THEME["accent"],
            font=("Segoe UI Semibold", 10),
            cursor="hand2",
        )
        self.bind("<Enter>", lambda _e: self.configure(bg=THEME["panel2"]))
        self.bind("<Leave>", lambda _e: self.configure(bg=THEME["panel"]))


class AutomationShell(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.platform_root = _platform_root()
        self.services = PlatformServices(self)
        self.page_cache: dict[str, tk.Widget] = {}
        self.current_page: tk.Widget | None = None
        self.module_integrations: dict[str, dict[str, Any]] = {}
        self.module_buttons: list[tk.Widget] = []

        self.title(f"AutomationPlatform Control Center — Modular Shell v{SHELL_VERSION}")
        self.geometry("1280x820")
        self.minsize(1040, 680)
        self.configure(bg=THEME["bg"])

        self._build_header()
        self._build_body()
        self.discover_modules(rebuild_menu=True)
        self.show_page("home")
        self.after(350, self.refresh_status)
        self.after(2500, self._status_loop)

    def _build_header(self) -> None:
        header = tk.Frame(self, bg=THEME["panel"], height=76)
        header.pack(side="top", fill="x")
        header.pack_propagate(False)

        left = tk.Frame(header, bg=THEME["panel"])
        left.pack(side="left", padx=22, pady=11)
        tk.Label(left, text="AutomationPlatform", bg=THEME["panel"], fg=THEME["text"], font=("Segoe UI Semibold", 19)).pack(anchor="w")
        tk.Label(left, text=f"MODULAR CONTROL SHELL  •  UI API {MODULE_UI_API}", bg=THEME["panel"], fg=THEME["accent"], font=("Segoe UI", 8)).pack(anchor="w")

        self.status_bar = tk.Frame(header, bg=THEME["panel"])
        self.status_bar.pack(side="right", padx=18)
        self.status_labels: dict[str, tk.Label] = {}
        for key in ("PYTHON", "CHROME", "CDP", "MODULES"):
            box = tk.Frame(self.status_bar, bg=THEME["panel2"], padx=10, pady=6)
            box.pack(side="left", padx=4)
            tk.Label(box, text=key, bg=THEME["panel2"], fg=THEME["muted"], font=("Segoe UI", 7)).pack()
            label = tk.Label(box, text="…", bg=THEME["panel2"], fg=THEME["warning"], font=("Segoe UI Semibold", 9))
            label.pack()
            self.status_labels[key] = label

    def _build_body(self) -> None:
        body = tk.Frame(self, bg=THEME["bg"])
        body.pack(fill="both", expand=True)

        self.sidebar = tk.Frame(body, bg=THEME["panel"], width=248)
        self.sidebar.pack(side="left", fill="y")
        self.sidebar.pack_propagate(False)

        self.nav_static = tk.Frame(self.sidebar, bg=THEME["panel"])
        self.nav_static.pack(fill="x", pady=(12, 0))
        self._nav(self.nav_static, "⌂  ГЛАВНАЯ", "home")
        self._nav(self.nav_static, "⌘  КОМАНДЫ", "commands")
        self._nav(self.nav_static, "⚙  ПАРАМЕТРЫ", "parameters")

        tk.Label(self.sidebar, text="МОДУЛИ", bg=THEME["panel"], fg=THEME["muted"], font=("Segoe UI Semibold", 8), anchor="w", padx=18).pack(fill="x", pady=(18, 5))
        self.module_nav = tk.Frame(self.sidebar, bg=THEME["panel"])
        self.module_nav.pack(fill="x")

        tk.Label(self.sidebar, text="СИСТЕМА", bg=THEME["panel"], fg=THEME["muted"], font=("Segoe UI Semibold", 8), anchor="w", padx=18).pack(fill="x", pady=(18, 5))
        self.nav_system = tk.Frame(self.sidebar, bg=THEME["panel"])
        self.nav_system.pack(fill="x")
        self._nav(self.nav_system, "▦  ЦЕНТР МОДУЛЕЙ", "module_center")
        self._nav(self.nav_system, "▤  РЕЗУЛЬТАТЫ", "results")
        self._nav(self.nav_system, "≡  ЛОГИ", "logs")

        bottom = tk.Frame(self.sidebar, bg=THEME["panel"])
        bottom.pack(side="bottom", fill="x", padx=14, pady=14)
        tk.Button(bottom, text="ОБНОВИТЬ PLATFORM", command=self.update_platform, bg=THEME["accent2"], fg="#06111a", activebackground=THEME["accent"], bd=0, pady=9, font=("Segoe UI Semibold", 9), cursor="hand2").pack(fill="x")

        self.workspace = tk.Frame(body, bg=THEME["bg"])
        self.workspace.pack(side="left", fill="both", expand=True, padx=18, pady=18)

    def _nav(self, parent: tk.Misc, label: str, page_id: str) -> None:
        NavButton(parent, label, lambda p=page_id: self.show_page(p)).pack(fill="x")

    def _clear_module_nav(self) -> None:
        for w in self.module_buttons:
            w.destroy()
        self.module_buttons.clear()

    def discover_modules(self, rebuild_menu: bool = False) -> None:
        found: dict[str, dict[str, Any]] = {}
        modules_root = self.platform_root / "modules"
        modules_root.mkdir(parents=True, exist_ok=True)
        for folder in modules_root.iterdir():
            if not folder.is_dir():
                continue
            integration_path = folder / "platform_integration.json"
            if not integration_path.exists():
                continue
            try:
                data = json.loads(integration_path.read_text(encoding="utf-8-sig"))
                if int(data.get("ui_api", 0)) > MODULE_UI_API:
                    continue
                if data.get("ui_mode") != "embedded":
                    continue
                data["module_path"] = str(folder)
                found[str(data["module_id"])] = data
            except Exception:
                continue
        self.module_integrations = found

        if rebuild_menu:
            self._clear_module_nav()
            if not found:
                label = tk.Label(self.module_nav, text="  Нет установленных UI-модулей", bg=THEME["panel"], fg=THEME["muted"], anchor="w", padx=18, pady=8, font=("Segoe UI", 9))
                label.pack(fill="x")
                self.module_buttons.append(label)
            for module_id, meta in sorted(found.items(), key=lambda item: item[1].get("menu_label", item[0]).lower()):
                label = f"◆  {meta.get('menu_label', meta.get('name', module_id))}"
                button = NavButton(self.module_nav, label, lambda m=module_id: self.show_module(m))
                button.pack(fill="x")
                self.module_buttons.append(button)
        self.refresh_status()

    def _hide_current(self) -> None:
        if self.current_page is not None:
            self.current_page.pack_forget()

    def _activate(self, widget: tk.Widget) -> None:
        self._hide_current()
        self.current_page = widget
        widget.pack(fill="both", expand=True)
        callback = getattr(widget, "on_show", None)
        if callable(callback):
            try:
                callback()
            except Exception:
                pass

    def show_page(self, page_id: str) -> None:
        if page_id not in self.page_cache:
            builders = {
                "home": self._page_home,
                "commands": self._page_commands,
                "parameters": self._page_parameters,
                "module_center": self._page_module_center,
                "results": self._page_results,
                "logs": self._page_logs,
            }
            builder = builders.get(page_id)
            if not builder:
                return
            self.page_cache[page_id] = builder()
        self._activate(self.page_cache[page_id])

    def show_module(self, module_id: str) -> None:
        cache_id = f"module:{module_id}"
        if cache_id in self.page_cache:
            self._activate(self.page_cache[cache_id])
            return
        meta = self.module_integrations.get(module_id)
        if not meta:
            messagebox.showwarning("AutomationPlatform", "Модуль не установлен или не зарегистрировал embedded UI.")
            return
        try:
            module_path = Path(meta["module_path"])
            ui_file = module_path / str(meta["ui_file"])
            class_name = str(meta["entry_class"])
            if not ui_file.exists():
                raise FileNotFoundError(ui_file)
            spec = importlib.util.spec_from_file_location(f"ap_module_{module_id}", ui_file)
            if spec is None or spec.loader is None:
                raise RuntimeError("Cannot create module import specification")
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            panel_class = getattr(module, class_name)
            panel = panel_class(self.workspace, self.services)
            self.page_cache[cache_id] = panel
            self._activate(panel)
        except Exception as exc:
            panel = self._error_panel(f"Не удалось открыть модуль {module_id}", str(exc))
            self.page_cache[cache_id] = panel
            self._activate(panel)

    def _page_title(self, parent: tk.Misc, title: str, subtitle: str = "") -> tk.Frame:
        head = tk.Frame(parent, bg=THEME["bg"])
        head.pack(fill="x", pady=(4, 16))
        tk.Label(head, text=title, bg=THEME["bg"], fg=THEME["text"], font=("Segoe UI Semibold", 20)).pack(anchor="w")
        if subtitle:
            tk.Label(head, text=subtitle, bg=THEME["bg"], fg=THEME["muted"], font=("Segoe UI", 9)).pack(anchor="w", pady=(3, 0))
        return head

    def _card(self, parent: tk.Misc, title: str, value: str, command: Callable[[], None] | None = None) -> tk.Frame:
        frame = tk.Frame(parent, bg=THEME["card"], padx=16, pady=14, highlightthickness=1, highlightbackground=THEME["line"])
        tk.Label(frame, text=title, bg=THEME["card"], fg=THEME["muted"], font=("Segoe UI", 8)).pack(anchor="w")
        tk.Label(frame, text=value, bg=THEME["card"], fg=THEME["text"], font=("Segoe UI Semibold", 11)).pack(anchor="w", pady=(5, 0))
        if command:
            tk.Button(frame, text="ОТКРЫТЬ", command=command, bg=THEME["accent2"], fg="#06111a", bd=0, padx=12, pady=5, cursor="hand2").pack(anchor="w", pady=(12, 0))
        return frame

    def _page_home(self) -> tk.Frame:
        page = tk.Frame(self.workspace, bg=THEME["bg"])
        self._page_title(page, "Главная", "Центральная панель AutomationPlatform — одно окно для платформы и всех модулей")
        cards = tk.Frame(page, bg=THEME["bg"])
        cards.pack(fill="x")
        items = [
            ("Chrome Debug", "Общий браузер / CDP :9222", self.start_chrome_debug),
            ("Chrome Profile", str(self.services.chrome_profile), lambda: self.services.open_folder(self.services.chrome_profile)),
            ("Platform Root", str(self.platform_root), lambda: self.services.open_folder(self.platform_root)),
        ]
        for i, (title, value, cmd) in enumerate(items):
            card = self._card(cards, title, value, cmd)
            card.grid(row=0, column=i, sticky="nsew", padx=(0 if i == 0 else 8, 0))
            cards.columnconfigure(i, weight=1)
        text = (
            "Модульные панели открываются в центральной области этого окна. "
            "При переключении они не закрываются: AutomationPlatform скрывает предыдущий Frame и показывает выбранный, сохраняя его состояние."
        )
        info = tk.Label(page, text=text, wraplength=850, justify="left", bg=THEME["panel2"], fg=THEME["text"], padx=18, pady=18, font=("Segoe UI", 10))
        info.pack(fill="x", pady=18)
        return page

    def _page_commands(self) -> tk.Frame:
        page = tk.Frame(self.workspace, bg=THEME["bg"])
        self._page_title(page, "Команды", "Command Router / automation.cmd")
        top = tk.Frame(page, bg=THEME["bg"])
        top.pack(fill="both", expand=True)
        left = tk.Frame(top, bg=THEME["panel2"])
        left.pack(side="left", fill="y")
        right = tk.Frame(top, bg=THEME["bg"])
        right.pack(side="left", fill="both", expand=True, padx=(12, 0))
        lb = tk.Listbox(left, width=34, bg=THEME["panel2"], fg=THEME["text"], selectbackground=THEME["accent2"], bd=0, highlightthickness=0, font=("Consolas", 9))
        lb.pack(fill="both", expand=True, padx=8, pady=8)
        out = tk.Text(right, bg="#050b11", fg=THEME["text"], insertbackground=THEME["accent"], bd=0, font=("Consolas", 9), wrap="word")
        out.pack(fill="both", expand=True)
        catalog = self.services.read_json(self.platform_root / "commands" / "catalog.json", {}) or {}
        commands = catalog.get("commands", catalog if isinstance(catalog, list) else [])
        names: list[str] = []
        if isinstance(commands, list):
            for item in commands:
                name = item.get("name") if isinstance(item, dict) else str(item)
                if name:
                    names.append(str(name))
        elif isinstance(commands, dict):
            names = list(commands.keys())
        for name in sorted(names):
            lb.insert("end", name)

        def run_selected() -> None:
            sel = lb.curselection()
            if not sel:
                return
            name = lb.get(sel[0])
            out.delete("1.0", "end")
            out.insert("end", f"> automation.cmd run {name}\n")
            cmd = [str(self.platform_root / "automation.cmd"), "run", name]
            self.services.run_process(cmd, on_output=lambda line: (out.insert("end", line + "\n"), out.see("end")))

        tk.Button(right, text="ВЫПОЛНИТЬ ВЫБРАННУЮ КОМАНДУ", command=run_selected, bg=THEME["accent"], fg="#06111a", bd=0, pady=8, cursor="hand2").pack(fill="x", pady=(10, 0))
        return page

    def _page_parameters(self) -> tk.Frame:
        page = tk.Frame(self.workspace, bg=THEME["bg"])
        self._page_title(page, "Параметры", "Общие значения data/shared_values.json")
        editor = tk.Text(page, bg="#050b11", fg=THEME["text"], insertbackground=THEME["accent"], bd=0, font=("Consolas", 10))
        editor.pack(fill="both", expand=True)
        path = self.platform_root / "data" / "shared_values.json"
        try:
            editor.insert("1.0", path.read_text(encoding="utf-8-sig"))
        except Exception:
            editor.insert("1.0", '{\n  "values": {}\n}')

        def save() -> None:
            try:
                parsed = json.loads(editor.get("1.0", "end"))
                self.services.write_json(path, parsed)
                messagebox.showinfo("AutomationPlatform", "Параметры сохранены.")
            except Exception as exc:
                messagebox.showerror("AutomationPlatform", f"JSON error: {exc}")

        tk.Button(page, text="СОХРАНИТЬ ПАРАМЕТРЫ", command=save, bg=THEME["accent"], fg="#06111a", bd=0, pady=8, cursor="hand2").pack(fill="x", pady=(10, 0))
        return page

    def _page_module_center(self) -> tk.Frame:
        page = tk.Frame(self.workspace, bg=THEME["bg"])
        self._page_title(page, "Центр модулей", "Установка, обновление и переход к панелям модулей")
        content = tk.Frame(page, bg=THEME["bg"])
        content.pack(fill="both", expand=True)

        dce = tk.Frame(content, bg=THEME["card"], padx=18, pady=16, highlightthickness=1, highlightbackground=THEME["line"])
        dce.pack(fill="x")
        tk.Label(dce, text="Dynamic Conversation Exporter", bg=THEME["card"], fg=THEME["text"], font=("Segoe UI Semibold", 13)).pack(anchor="w")
        tk.Label(dce, text="GitHub: 1777maxim7771/Dynamic_Conversation_Exporter", bg=THEME["card"], fg=THEME["muted"], font=("Segoe UI", 9)).pack(anchor="w", pady=(3, 10))
        state = tk.Label(dce, text="", bg=THEME["card"], fg=THEME["warning"], font=("Segoe UI Semibold", 9))
        state.pack(anchor="w")
        row = tk.Frame(dce, bg=THEME["card"])
        row.pack(fill="x", pady=(12, 0))

        def refresh_state() -> None:
            installed = "dynamic_conversation_exporter" in self.module_integrations
            state.configure(text="УСТАНОВЛЕН • EMBEDDED UI" if installed else "НЕ УСТАНОВЛЕН", fg=THEME["ok"] if installed else THEME["warning"])
            open_btn.configure(state="normal" if installed else "disabled")

        def install() -> None:
            script = self.platform_root / "installer" / "OPTIONAL_MODULES_MANAGER.ps1"
            if not script.exists():
                messagebox.showerror("AutomationPlatform", f"Не найден {script}")
                return
            state.configure(text="УСТАНОВКА / ОБНОВЛЕНИЕ…", fg=THEME["warning"])
            cmd = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script), "-Root", str(self.platform_root), "-ManifestUrl", "https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/platform_manifest.json", "-InstallDynamicConversationExporter"]

            def done(rc: int, output: str) -> None:
                self.discover_modules(rebuild_menu=True)
                refresh_state()
                if rc != 0:
                    messagebox.showerror("AutomationPlatform", "Установка модуля завершилась ошибкой. Откройте logs/latest_optional_modules.log")
                else:
                    messagebox.showinfo("AutomationPlatform", "Модуль установлен/обновлён.")

            self.services.run_process(cmd, on_done=done)

        tk.Button(row, text="УСТАНОВИТЬ / ОБНОВИТЬ", command=install, bg=THEME["accent"], fg="#06111a", bd=0, padx=14, pady=8, cursor="hand2").pack(side="left")
        open_btn = tk.Button(row, text="ОТКРЫТЬ ПАНЕЛЬ", command=lambda: self.show_module("dynamic_conversation_exporter"), bg=THEME["accent2"], fg="#06111a", bd=0, padx=14, pady=8, cursor="hand2")
        open_btn.pack(side="left", padx=8)
        tk.Button(row, text="ПЕРЕСКАНИРОВАТЬ", command=lambda: (self.discover_modules(rebuild_menu=True), refresh_state()), bg=THEME["panel2"], fg=THEME["text"], bd=0, padx=14, pady=8, cursor="hand2").pack(side="left")
        page.after(50, refresh_state)
        return page

    def _page_results(self) -> tk.Frame:
        page = tk.Frame(self.workspace, bg=THEME["bg"])
        self._page_title(page, "Результаты", "JSON и другие результаты AutomationPlatform")
        text = tk.Text(page, bg="#050b11", fg=THEME["text"], bd=0, font=("Consolas", 9))
        text.pack(fill="both", expand=True)
        candidates = list((self.platform_root / "data").glob("*.json"))
        for path in sorted(candidates, key=lambda p: p.stat().st_mtime, reverse=True)[:30]:
            text.insert("end", f"{path.name}\n")
        return page

    def _page_logs(self) -> tk.Frame:
        page = tk.Frame(self.workspace, bg=THEME["bg"])
        self._page_title(page, "Логи", "Последние журналы платформы и модулей")
        text = tk.Text(page, bg="#050b11", fg=THEME["text"], bd=0, font=("Consolas", 9), wrap="none")
        text.pack(fill="both", expand=True)

        def refresh() -> None:
            text.delete("1.0", "end")
            for name in ("latest_bootstrap.log", "latest_finalizer.log", "latest_optional_modules.log", "latest_chrome_runtime.log", "latest_python_runtime.log"):
                path = self.platform_root / "logs" / name
                if path.exists():
                    text.insert("end", f"\n===== {name} =====\n")
                    try:
                        lines = path.read_text(encoding="utf-8-sig", errors="replace").splitlines()[-120:]
                        text.insert("end", "\n".join(lines) + "\n")
                    except Exception as exc:
                        text.insert("end", f"ERROR: {exc}\n")
            text.see("end")

        tk.Button(page, text="ОБНОВИТЬ ЛОГИ", command=refresh, bg=THEME["accent2"], fg="#06111a", bd=0, pady=7, cursor="hand2").pack(fill="x", pady=(10, 0))
        page.on_show = refresh  # type: ignore[attr-defined]
        refresh()
        return page

    def _error_panel(self, title: str, details: str) -> tk.Frame:
        page = tk.Frame(self.workspace, bg=THEME["bg"])
        self._page_title(page, title)
        tk.Label(page, text=details, bg=THEME["panel2"], fg=THEME["danger"], justify="left", wraplength=800, padx=18, pady=18).pack(fill="x")
        return page

    def start_chrome_debug(self) -> None:
        launcher = self.platform_root / "START_CHROME_DEBUG.cmd"
        if not launcher.exists():
            messagebox.showerror("AutomationPlatform", "START_CHROME_DEBUG.cmd не найден.")
            return
        url = simpledialog.askstring("Chrome Debug", "Какой сайт открыть?\nОставьте пустым, чтобы использовать сохранённый browser.start_url.", parent=self)
        cmd = [str(launcher)]
        if url and url.strip():
            cmd.append(url.strip())
        self.services.run_process(cmd)

    def update_platform(self) -> None:
        updater = self.platform_root / "UPDATE_PLATFORM.cmd"
        if not updater.exists():
            messagebox.showerror("AutomationPlatform", "UPDATE_PLATFORM.cmd не найден.")
            return
        self.services.run_process([str(updater)], on_done=lambda _rc, _out: self.discover_modules(rebuild_menu=True))

    def refresh_status(self) -> None:
        py = self.services.python_exe
        py_ok = py.exists()
        chrome = os.environ.get("AUTOMATION_PLATFORM_CHROME", "")
        chrome_ok = bool(chrome and Path(chrome).exists())
        if not chrome_ok:
            candidates = [
                Path(os.environ.get("ProgramFiles", "")) / "Google/Chrome/Application/chrome.exe",
                Path(os.environ.get("LOCALAPPDATA", "")) / "Google/Chrome/Application/chrome.exe",
            ]
            chrome_ok = any(p.exists() for p in candidates)
        cdp_ok = False
        try:
            with socket.create_connection(("127.0.0.1", 9222), timeout=0.18):
                cdp_ok = True
        except OSError:
            pass
        states = {
            "PYTHON": ("OK" if py_ok else "ERR", THEME["ok"] if py_ok else THEME["danger"]),
            "CHROME": ("OK" if chrome_ok else "ERR", THEME["ok"] if chrome_ok else THEME["danger"]),
            "CDP": ("ONLINE" if cdp_ok else "OFF", THEME["ok"] if cdp_ok else THEME["warning"]),
            "MODULES": (str(len(self.module_integrations)), THEME["accent"]),
        }
        for key, (text, color) in states.items():
            self.status_labels[key].configure(text=text, fg=color)

    def _status_loop(self) -> None:
        self.refresh_status()
        self.after(2500, self._status_loop)


if __name__ == "__main__":
    AutomationShell().mainloop()
