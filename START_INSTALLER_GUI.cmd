@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0START_PLATFORM_INSTALLER.ps1" -DefaultRoot "D:\AutomationPlatform" -ManifestUrl "https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/platform_manifest.json"
endlocal
