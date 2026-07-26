param(
    [string]$Root = "D:\AutomationPlatform",
    [string]$ManifestUrl = "https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/platform_manifest.json"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ManagerVersion = "2026.07.26.1"

$Root = $Root.Trim().Trim([char]0x22,[char]0x27).TrimEnd('\','/').Trim()
if (-not $Root) { throw "Root path is empty." }

$logDir = Join-Path $Root "logs"
$downloads = Join-Path $Root "_bootstrap\downloads"
New-Item -ItemType Directory -Force -Path $Root,$logDir,$downloads | Out-Null
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $logDir "chrome_runtime_$stamp.log"
$latestLog = Join-Path $logDir "latest_chrome_runtime.log"
"=== AutomationPlatform Chrome Runtime Manager $ManagerVersion ===" | Set-Content -Encoding UTF8 $logFile

function Log([string]$Text,[string]$Level="INFO") {
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$Level,$Text
    Write-Host $line
    Add-Content -Encoding UTF8 -Path $logFile -Value $line
}
function Warn([string]$Text) { Log $Text "WARN" }
function Find-Chrome {
    $candidates = @(
        (Join-Path $env:ProgramFiles "Google\Chrome\Application\chrome.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe"),
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe")
    )
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    try {
        $reg = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" -ErrorAction SilentlyContinue
        if ($reg -and $reg.'(default)' -and (Test-Path $reg.'(default)')) { return [string]$reg.'(default)' }
    } catch {}
    return $null
}
function Get-Version([string]$Path) {
    if (-not $Path -or -not (Test-Path $Path)) { return $null }
    try { return ([string](Get-Item $Path).VersionInfo.ProductVersion).Trim() } catch { return $null }
}
function Is-Older([string]$Current,[string]$Latest) {
    try { return ([version]$Current -lt [version]$Latest) } catch { return $false }
}
function Chrome-Running {
    return $null -ne (Get-Process chrome -ErrorAction SilentlyContinue | Select-Object -First 1)
}
function Download([string]$Url,[string]$Dest) {
    Log "DOWNLOAD $Url"
    Log "        -> $Dest"
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Dest
    if (-not (Test-Path $Dest)) { throw "Download failed: $Url" }
    Log ("DOWNLOADED {0} bytes" -f (Get-Item $Dest).Length)
}
function Install-Msi([string]$Url) {
    $pkg = Join-Path $downloads "google_chrome_installer.msi"
    Download $Url $pkg
    Log "Starting Google Chrome MSI"
    $p = Start-Process -FilePath "msiexec.exe" -ArgumentList @('/i',"`"$pkg`"",'/qn','/norestart') -Wait -PassThru
    Log "Chrome MSI exit code: $($p.ExitCode)"
    return [int]$p.ExitCode
}

try {
    Log "Root=$Root"
    Log "Manifest=$ManifestUrl"
    $manifest = Invoke-RestMethod -Uri ($ManifestUrl + "?nocache=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())")
    $chrome = Find-Chrome
    $installed = Get-Version $chrome
    $latest = $null
    try {
        $versionUrl = [string]$manifest.chrome.stable_version_url
        $info = Invoke-RestMethod -Uri ($versionUrl + "?nocache=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())")
        $latest = [string]$info.channels.Stable.version
    } catch { Warn "Could not query latest Chrome version: $($_.Exception.Message)" }

    Log "Chrome path=$chrome"
    Log "Installed=$installed LatestStable=$latest Running=$(Chrome-Running)"
    $installerUrl = [string]$manifest.chrome.google_chrome_installer_url

    if (-not $chrome) {
        Log "[CHROME][INSTALL] Google Chrome is missing. Installation is required."
        $rc = Install-Msi $installerUrl
        if ($rc -ne 0 -and $rc -ne 3010) { throw "Chrome installation failed with exit code $rc" }
        Start-Sleep -Seconds 2
        $chrome = Find-Chrome
        if (-not $chrome) { throw "Chrome installer completed but chrome.exe was not found." }
        $installed = Get-Version $chrome
        Log "[CHROME][OK] Installed=$installed Path=$chrome"
    }
    elseif ($latest -and $installed -and (Is-Older $installed $latest)) {
        if (Chrome-Running) {
            Warn "[CHROME][DEFER_UPDATE] Update $installed -> $latest is available, but Chrome is running. Existing Chrome remains usable; update will be retried on a later platform run."
        } else {
            Log "[CHROME][UPDATE] Attempting $installed -> $latest"
            try {
                $rc = Install-Msi $installerUrl
                if ($rc -ne 0 -and $rc -ne 3010) {
                    Warn "[CHROME][UPDATE_FAILED_USING_EXISTING] MSI exit code $rc. Existing Chrome $installed remains usable; platform setup will continue."
                } else {
                    Start-Sleep -Seconds 2
                    $after = Find-Chrome
                    $afterVersion = Get-Version $after
                    if ($after) {
                        $chrome = $after
                        $installed = $afterVersion
                        Log "[CHROME][OK] Current version=$installed Path=$chrome"
                    } else {
                        throw "Chrome disappeared after update attempt."
                    }
                }
            } catch {
                $still = Find-Chrome
                if ($still) {
                    $chrome = $still
                    $installed = Get-Version $still
                    Warn "[CHROME][UPDATE_FAILED_USING_EXISTING] $($_.Exception.Message). Existing Chrome $installed remains usable."
                } else { throw }
            }
        }
    }
    else {
        Log "[CHROME][SKIP] Chrome is installed/current enough. Version=$installed Path=$chrome"
    }

    if (-not (Find-Chrome)) { throw "Final Chrome health check failed: chrome.exe is unavailable." }
    Copy-Item -Force $logFile $latestLog
    exit 0
}
catch {
    Log "FATAL: $($_.Exception.Message)" "ERROR"
    try { Log $_.ScriptStackTrace "ERROR" } catch {}
    try { Copy-Item -Force $logFile $latestLog } catch {}
    exit 1
}
