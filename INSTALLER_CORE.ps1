param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$ManifestUrl,
    [switch]$InstallPython,
    [switch]$InstallChrome,
    [switch]$InstallControlCenter,
    [switch]$CreateChromeProfile
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:LogFile = $null

function Ensure-Log {
    $logDir = Join-Path $Root "logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $script:LogFile = Join-Path $logDir ("install_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
    "=== AutomationPlatform install log $(Get-Date -Format o) ===" | Set-Content -Encoding UTF8 $script:LogFile
}

function Log([string]$Text) {
    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Text
    Write-Host $line
    if ($script:LogFile) { Add-Content -Encoding UTF8 -Path $script:LogFile -Value $line }
}

function Step([string]$Text) {
    Log "[STEP] $Text"
}

function Download([string]$Url, [string]$Dest) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dest) | Out-Null
    Log "Download: $Url"
    Log "      to: $Dest"
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Dest
    if (-not (Test-Path $Dest)) { throw "Download failed: $Url" }
    Log ("OK size={0} bytes" -f (Get-Item $Dest).Length)
}

function Sha([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

function PackageUrl([string]$ManifestUrlValue, $Item) {
    if ($Item.package_url) { return [string]$Item.package_url }
    if (-not $Item.package_path) { throw "Manifest item has no package_url/package_path." }
    $base = [Uri]$ManifestUrlValue
    return (New-Object System.Uri($base, ([string]$Item.package_path).Replace('\','/'))).AbsoluteUri
}

function RawBase([string]$ManifestUrlValue) {
    $u = [Uri]$ManifestUrlValue
    $path = $u.AbsolutePath
    $idx = $path.LastIndexOf('/')
    if ($idx -lt 0) { throw "Cannot resolve repository raw base from Manifest URL." }
    $basePath = $path.Substring(0, $idx + 1)
    return "$($u.Scheme)://$($u.Host)$basePath"
}

try {
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    Ensure-Log
    Step "Root = $Root"
    Step "Manifest = $ManifestUrl"
    Step "Flags: Python=$InstallPython Chrome=$InstallChrome CC=$InstallControlCenter Profile=$CreateChromeProfile"

    Step "Loading manifest"
    $manifest = Invoke-RestMethod -Uri $ManifestUrl
    $rawBase = RawBase $ManifestUrl
    Log "rawBase = $rawBase"

    $bootstrap   = Join-Path $Root "_bootstrap"
    $downloads   = Join-Path $bootstrap "downloads"
    $runtime     = Join-Path $Root "runtime"
    $pythonDir   = Join-Path $runtime "python"
    $chromeRoot  = Join-Path $runtime "chrome"
    $browser     = Join-Path $Root "browser"
    $profile     = Join-Path $browser "Chrome_Profile"
    $configDir   = Join-Path $Root "config"
    $installerDir = Join-Path $Root "installer"

    foreach ($d in @(
        $Root,$bootstrap,$downloads,$runtime,$chromeRoot,$browser,$configDir,$installerDir,
        (Join-Path $Root "modules"),(Join-Path $Root "data"),(Join-Path $Root "jobs"),
        (Join-Path $Root "logs"),(Join-Path $Root "_update")
    )) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
    }

    $pythonExe = Join-Path $pythonDir "python.exe"

    # ---- Python ----
    if ($InstallPython) {
        if (-not (Test-Path $pythonExe)) {
            Step "Installing local Python $($manifest.python.version)"
            $pyInstaller = Join-Path $downloads "python-$($manifest.python.version)-amd64.exe"
            try {
                Download ([string]$manifest.python.installer_url) $pyInstaller
            } catch {
                Log "Python download failed: $($_.Exception.Message)"
                Log "Skipping local Python install. You can install Python later."
                $InstallPython = $false
            }

            if ($InstallPython -and (Test-Path $pyInstaller)) {
                if ($manifest.python.sha256) {
                    $actual = Sha $pyInstaller
                    $expect = ([string]$manifest.python.sha256).ToLowerInvariant()
                    if ($actual -ne $expect) {
                        Log "Python SHA mismatch (continuing anyway)"
                        Log "  expected: $expect"
                        Log "  actual:   $actual"
                    }
                }
                $pyArgs = @(
                    "/quiet",
                    "InstallAllUsers=0",
                    "TargetDir=$pythonDir",
                    "PrependPath=0",
                    "AppendPath=0",
                    "AssociateFiles=0",
                    "Shortcuts=0",
                    "Include_launcher=0",
                    "InstallLauncherAllUsers=0",
                    "Include_doc=0",
                    "Include_test=0",
                    "Include_pip=1",
                    "Include_tcltk=1",
                    "Include_tools=1",
                    "Include_dev=1",
                    "Include_lib=1",
                    "Include_exe=1"
                )
                Log "Running Python installer..."
                $p = Start-Process -FilePath $pyInstaller -ArgumentList $pyArgs -Wait -PassThru
                Log "Python installer exit code: $($p.ExitCode)"
                if (-not (Test-Path $pythonExe)) {
                    Log "WARNING: python.exe not found after install. Continuing without local Python."
                }
            }
        } else {
            Step "Local Python already installed"
        }
    }

    # ---- Chrome for Testing ----
    $chromeExe = ""
    if ($InstallChrome) {
        Step "Installing/updating Chrome for Testing Stable"
        try {
            $cft = Invoke-RestMethod -Uri ([string]$manifest.chrome.cft_json_url)
            $stable = $cft.channels.Stable
            $platform = [string]$manifest.chrome.platform
            $download = $stable.downloads.chrome | Where-Object { $_.platform -eq $platform } | Select-Object -First 1
            if (-not $download) { throw "Chrome for Testing package not found for platform $platform" }

            $versionFile = Join-Path $chromeRoot "VERSION.txt"
            $installed = ""
            if (Test-Path $versionFile) { $installed = (Get-Content -Raw $versionFile).Trim() }

            Log "Chrome Stable version online: $($stable.version); installed: $installed"

            if ($installed -ne [string]$stable.version) {
                $zip = Join-Path $downloads "chrome-$($stable.version).zip"
                Download ([string]$download.url) $zip
                $stage = Join-Path $bootstrap "chrome_stage"
                Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
                New-Item -ItemType Directory -Force -Path $stage | Out-Null
                Expand-Archive -Path $zip -DestinationPath $stage -Force
                Get-ChildItem $chromeRoot -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                $srcChrome = Join-Path $stage "chrome-win64"
                if (-not (Test-Path $srcChrome)) {
                    # some builds nest differently
                    $srcChrome = Get-ChildItem $stage -Directory | Select-Object -First 1 | ForEach-Object { $_.FullName }
                }
                Copy-Item -Recurse -Force $srcChrome (Join-Path $chromeRoot "chrome-win64")
                Set-Content -Encoding ASCII $versionFile ([string]$stable.version)
                Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
            }
            $chromeExe = Join-Path $chromeRoot "chrome-win64\chrome.exe"
            if (-not (Test-Path $chromeExe)) {
                Log "WARNING: chrome.exe not found after install"
                $chromeExe = ""
            } else {
                Log "Chrome OK: $chromeExe"
            }
        } catch {
            Log "Chrome install failed: $($_.Exception.Message)"
            Log "Continuing without Chrome for Testing."
        }
    } else {
        $candidate = Join-Path $chromeRoot "chrome-win64\chrome.exe"
        if (Test-Path $candidate) { $chromeExe = $candidate }
    }

    if ($CreateChromeProfile) {
        Step "Creating/preserving Chrome Profile directory"
        New-Item -ItemType Directory -Force -Path $profile | Out-Null
    }

    # ---- Control Center ----
    if ($InstallControlCenter) {
        Step "Installing/updating Control Center $($manifest.control_center.version)"
        $pkg = Join-Path $downloads "ControlCenter-$($manifest.control_center.version).zip"

        $url = PackageUrl $ManifestUrl $manifest.control_center
        Download $url $pkg

        if ($manifest.control_center.sha256) {
            $actual = Sha $pkg
            $expect = ([string]$manifest.control_center.sha256).ToLowerInvariant()
            if ($actual -ne $expect) {
                Log "Control Center SHA mismatch (continuing with downloaded package)"
                Log "  expected: $expect"
                Log "  actual:   $actual"
            } else {
                Log "Control Center SHA OK"
            }
        }

        $stage = Join-Path $bootstrap "control_stage"
        Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        Expand-Archive -Path $pkg -DestinationPath $stage -Force
        Log "Extracted Control Center package"

        foreach ($name in @("control_center","core","commands")) {
            $src = Join-Path $stage $name
            $dst = Join-Path $Root $name
            if (Test-Path $src) {
                Remove-Item -Recurse -Force $dst -ErrorAction SilentlyContinue
                Copy-Item -Recurse -Force $src $dst
                Log "Copied $name"
            }
        }

        foreach ($name in @("START_CONTROL_CENTER.cmd","automation.cmd")) {
            $src = Join-Path $stage $name
            if (Test-Path $src) {
                Copy-Item -Force $src (Join-Path $Root $name)
                Log "Copied $name"
            }
        }

        $svSrc = Join-Path $stage "data\shared_values.json"
        $svDst = Join-Path $Root "data\shared_values.json"
        if ((Test-Path $svSrc) -and -not (Test-Path $svDst)) {
            Copy-Item -Force $svSrc $svDst
        }

        $modSrc = Join-Path $stage "modules\example_registration"
        $modDst = Join-Path $Root "modules\example_registration"
        if ((Test-Path $modSrc) -and -not (Test-Path $modDst)) {
            Copy-Item -Recurse -Force $modSrc $modDst
        }

        Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
    }

    if (-not $chromeExe) {
        $candidate = Join-Path $chromeRoot "chrome-win64\chrome.exe"
        if (Test-Path $candidate) { $chromeExe = $candidate }
    }

    $debugPort = 9222
    try { $debugPort = [int]$manifest.defaults.debug_port } catch {}

    $config = [ordered]@{
        schema_version = 1
        platform_api = 1
        root = $Root
        manifest_url = $ManifestUrl
        control_center_version = [string]$manifest.control_center.version
        python_exe = $pythonExe
        chrome_exe = $chromeExe
        chrome_profile = $profile
        cdp_host = "127.0.0.1"
        debug_port = $debugPort
    }
    $configPath = Join-Path $configDir "platform.json"
    $config | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $configPath
    Log "Wrote $configPath"

    Step "Installing local platform updater files"
    foreach ($name in @("START_PLATFORM_INSTALLER.ps1","INSTALLER_CORE.ps1","START_INSTALLER_GUI.cmd","INSTALL_AutomationPlatform.bat")) {
        try {
            Download ($rawBase + $name) (Join-Path $installerDir $name)
        } catch {
            Log "WARN: could not refresh $name - $($_.Exception.Message)"
        }
    }

    $rootUpdateCmd = @"
@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\START_PLATFORM_INSTALLER.ps1" -DefaultRoot "%~dp0"
endlocal
"@
    Set-Content -Encoding ASCII -Path (Join-Path $Root "UPDATE_PLATFORM.cmd") -Value $rootUpdateCmd

    Step "Done"
    Log "Root           : $Root"
    Log "Python         : $pythonExe"
    Log "Chrome         : $chromeExe"
    Log "Chrome Profile : $profile"
    Log "Updater        : $(Join-Path $Root 'UPDATE_PLATFORM.cmd')"
    Log "Log file       : $script:LogFile"
    exit 0
}
catch {
    $msg = $_.Exception.Message
    try { Log "FATAL: $msg" } catch { Write-Host "FATAL: $msg" }
    try { Log $_.ScriptStackTrace } catch {}
    Write-Error $msg
    exit 1
}
