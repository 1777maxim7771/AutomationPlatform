# AutomationPlatform

Modular Windows automation platform for `D:\AutomationPlatform`.

- One-file bootstrap from GitHub
- Project-local Python (embed preferred)
- **Official Google Chrome required** (Chrome for Testing is not used)
- Persistent debug profile: `browser\Chrome_Profile` (CDP port 9222)
- Control Center with dependency checks (`START_CONTROL_CENTER.cmd`)
- CLI: `automation.cmd` for GUI / scripts / AI agents
- Self-healing updates via `UPDATE_PLATFORM.cmd`

Quick start (PowerShell):

```powershell
irm https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/INSTALL_AutomationPlatform.ps1 | iex
```

Full docs (RU): see `README_RU.md`.
