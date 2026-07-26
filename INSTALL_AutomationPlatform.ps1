param(
    [string]$Root = "D:\AutomationPlatform",
    [string]$ManifestUrl = "https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/platform_manifest.json",
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoRaw = "https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main"
$tempDir = Join-Path $env:TEMP "AutomationPlatform_Bootstrap"
$runner = Join-Path $tempDir "BOOTSTRAP_RUNNER.ps1"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " AutomationPlatform - INSTALL / UPDATE / REPAIR" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Root: $Root"
Write-Host " Repo: github.com/1777maxim7771/AutomationPlatform"
Write-Host ""
Write-Host "Downloading latest bootstrap runner from GitHub..." -ForegroundColor Yellow

$url = "$RepoRaw/BOOTSTRAP_RUNNER.ps1?nocache=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $runner
if (-not (Test-Path $runner)) { throw "BOOTSTRAP_RUNNER.ps1 was not downloaded." }
try { Unblock-File $runner -ErrorAction SilentlyContinue } catch {}

$args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$runner,'-Root',$Root,'-ManifestUrl',$ManifestUrl)
if ($NoLaunch) { $args += '-NoLaunch' }

& powershell.exe @args
exit $LASTEXITCODE
