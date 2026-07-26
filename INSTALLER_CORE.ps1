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
$CoreVersion = "2026.07.26.2"

$Root = $Root.Trim().Trim([char]0x22, [char]0x27).TrimEnd('\','/').Trim()
if (-not $Root) { throw "-Root is empty." }

$script:LogFile = $null
$script:Status = [ordered]@{
    schema_version = 1
    generated_at = (Get-Date).ToString("o")
    installer_core_version = $CoreVersion
    overall_status = "running"
    root = $Root
    components = [ordered]@{
        python = [ordered]@{}
        chrome = [ordered]@{}
        control_center = [ordered]@{}
        chrome_profile = [ordered]@{}
        launchers = [ordered]@{}
    }
}

function Ensure-Log {
    $logDir = Join-Path $Root "logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $script:LogFile = Join-Path $logDir ("install_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
    "=== AutomationPlatform Installer Core $CoreVersion ===" | Set-Content -Encoding UTF8 $script:LogFile
}

function Log([string]$Text, [string]$Level = "INFO") {
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Text
    Write-Host $line
    if ($script:LogFile) { Add-Content -Encoding UTF8 -Path $script:LogFile -Value $line }
}

function Action([string]$Component, [string]$ActionName, [string]$Text) {
    Log "[$Component][$ActionName] $Text"
}

function Save-Status {
    try {
        $dataDir = Join-Path $Root "data"
        New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
        $statusPath = Join-Path $dataDir "platform_status.json"
        $script:Status.generated_at = (Get-Date).ToString("o")
        $script:Status | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $statusPath
        Log "Status file: $statusPath"
    } catch {
        Log "Could not write platform_status.json: $($_.Exception.Message)" "WARN"
    }
}

function Download([string]$Url, [string]$Dest) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dest) | Out-Null
    $sep = if ($Url -match '\?') { '&' } else { '?' }
    $fetchUrl = $Url
    if ($Url -match 'raw\.githubusercontent\.com') {
        $fetchUrl = "$Url$sep`nocache=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
    }
    Log "Download: $fetchUrl"
    Log "      to: $Dest"
    Invoke-WebRequest -UseBasicParsing -Uri $fetchUrl -OutFile $Dest
    if (-not (Test-Path $Dest)) { throw "Download failed: $Url" }
    Log ("Downloaded {0} bytes" -f (Get-Item $Dest).Length)
}

function Sha([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

function RawBase([string]$ManifestUrlValue) {
    $u = [Uri]$ManifestUrlValue
    $path = $u.AbsolutePath
    $idx = $path.LastIndexOf('/')
    if ($idx -lt 0) { throw "Cannot resolve raw repository base." }
    return "$($u.Scheme)://$($u.Host)$($path.Substring(0, $idx + 1))"
}

function PackageUrl([string]$ManifestUrlValue, $Item) {
    if ($Item.package_url) { return [string]$Item.package_url }
    if (-not $Item.package_path) { throw "Manifest item has no package path." }
    return (New-Object System.Uri([Uri]$ManifestUrlValue, ([string]$Item.package_path).Replace('\','/'))).AbsoluteUri
}

function Get-PythonVersion([string]$PythonPath) {
    if (-not (Test-Path $PythonPath)) { return $null }
    try {
        $v = & $PythonPath -c "import sys; print('.'.join(map(str,sys.version_info[:3])))" 2>$null
        if ($LASTEXITCODE -eq 0 -and $v) { return ([string]$v).Trim() }
    } catch {}
    return $null
}

function Test-Tkinter([string]$PythonPath) {
    if (-not (Test-Path $PythonPath)) { return $false }
    try {
        $null = & $PythonPath -c "import tkinter; print(tkinter.TkVersion)" 2>$null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

function Install-PythonFull([string]$InstallerPath, [string]$TargetDir) {
    if (Test-Path $TargetDir) {
        Action "PYTHON" "REPAIR" "Removing incomplete/outdated local runtime: $TargetDir"
        Remove-Item -Recurse -Force $TargetDir -ErrorAction Stop
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $TargetDir) | Out-Null

    $args = @(
        '/quiet',
        'InstallAllUsers=0',
        "TargetDir=`"$TargetDir`"",
        'PrependPath=0',
        'AppendPath=0',
        'AssociateFiles=0',
        'Shortcuts=0',
        'Include_launcher=0',
        'InstallLauncherAllUsers=0',
        'Include_doc=0',
        'Include_test=0',
        'Include_pip=1',
        'Include_tcltk=1',
        'Include_tools=1',
        'Include_dev=1',
        'Include_lib=1',
        'Include_exe=1'
    )

    Action "PYTHON" "INSTALL" "Running full CPython installer with Tcl/Tk"
    $p = Start-Process -FilePath $InstallerPath -ArgumentList $args -Wait -PassThru
    Log "Python installer exit code: $($p.ExitCode)"
    if ($p.ExitCode -ne 0) { throw "Python installer failed with exit code $($p.ExitCode)" }
}

function Find-SystemChrome {
    $candidates = @(
        (Join-Path $env:ProgramFiles "Google\Chrome\Application\chrome.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe"),
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe")
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    try {
        $reg = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" -ErrorAction SilentlyContinue
        if ($reg -and $reg.'(default)' -and (Test-Path $reg.'(default)')) { return [string]$reg.'(default)' }
    } catch {}
    return $null
}

function Get-ChromeVersion([string]$ChromePath) {
    if (-not $ChromePath -or -not (Test-Path $ChromePath)) { return $null }
    try { return ([string](Get-Item $ChromePath).VersionInfo.ProductVersion).Trim() } catch { return $null }
}

function Version-LessThan([string]$Current, [string]$Expected) {
    try { return ([version]$Current -lt [version]$Expected) } catch { return $false }
}

function Install-GoogleChrome([string]$DownloadsDir, [string]$InstallerUrl, [string]$Kind) {
    if (-not $InstallerUrl) { throw "Chrome installer URL is empty." }
    if (-not $Kind) { $Kind = "msi" }
    $ext = if ($Kind -eq "msi") { "msi" } else { "exe" }
    $pkg = Join-Path $DownloadsDir "google_chrome_installer.$ext"
    Download $InstallerUrl $pkg
    Action "CHROME" "INSTALL_UPDATE" "Installing latest official Google Chrome"
    if ($Kind -eq "msi") {
        $p = Start-Process -FilePath "msiexec.exe" -ArgumentList @('/i',"`"$pkg`"",'/qn','/norestart') -Wait -PassThru
        Log "Chrome MSI exit code: $($p.ExitCode)"
        if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw "Chrome MSI failed with exit code $($p.ExitCode)" }
    } else {
        $p = Start-Process -FilePath $pkg -ArgumentList @('/silent','/install') -Wait -PassThru
        Log "Chrome installer exit code: $($p.ExitCode)"
        if ($p.ExitCode -ne 0) { throw "Chrome installer failed with exit code $($p.ExitCode)" }
    }
    Start-Sleep -Seconds 3
    return (Find-SystemChrome)
}

try {
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    Ensure-Log
    Log "Root=$Root"
    Log "Manifest=$ManifestUrl"
    Log "Flags Python=$InstallPython Chrome=$InstallChrome ControlCenter=$InstallControlCenter Profile=$CreateChromeProfile"

    $manifest = Invoke-RestMethod -Uri ($ManifestUrl + "?nocache=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())")
    $rawBase = RawBase $ManifestUrl
    Log "Manifest schema=$($manifest.schema_version)"

    $bootstrap = Join-Path $Root "_bootstrap"
    $downloads = Join-Path $bootstrap "downloads"
    $runtime = Join-Path $Root "runtime"
    $pythonDir = Join-Path $runtime "python"
    $pythonExe = Join-Path $pythonDir "python.exe"
    $browser = Join-Path $Root "browser"
    $profile = Join-Path $browser "Chrome_Profile"
    $configDir = Join-Path $Root "config"
    $installerDir = Join-Path $Root "installer"
    $dataDir = Join-Path $Root "data"

    foreach ($d in @($bootstrap,$downloads,$runtime,$browser,$configDir,$installerDir,$dataDir,(Join-Path $Root 'modules'),(Join-Path $Root 'jobs'),(Join-Path $Root 'logs'),(Join-Path $Root '_update'))) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
    }

    # ---------------- Python ----------------
    $expectedPy = [string]$manifest.python.version
    $installedPy = Get-PythonVersion $pythonExe
    $tkOk = Test-Tkinter $pythonExe
    $pythonAction = "SKIP"
    $needPython = (-not $installedPy) -or ($installedPy -ne $expectedPy) -or (-not $tkOk)

    if ($needPython) {
        if (-not $InstallPython) { throw "Python requires install/repair but InstallPython is disabled." }
        if (-not $installedPy) { $pythonAction = "INSTALL" }
        elseif ($installedPy -ne $expectedPy) { $pythonAction = "UPDATE" }
        else { $pythonAction = "REPAIR" }
        Action "PYTHON" $pythonAction "Expected=$expectedPy Installed=$installedPy tkinter=$tkOk"

        $pyInstaller = Join-Path $downloads "python-$expectedPy-amd64.exe"
        $downloadPython = $true
        if (Test-Path $pyInstaller) {
            $downloadPython = $false
            if ($manifest.python.sha256) {
                $downloadPython = ((Sha $pyInstaller) -ne ([string]$manifest.python.sha256).ToLowerInvariant())
            }
        }
        if ($downloadPython) { Download ([string]$manifest.python.installer_url) $pyInstaller }
        if ($manifest.python.sha256) {
            $actualPySha = Sha $pyInstaller
            $expectedPySha = ([string]$manifest.python.sha256).ToLowerInvariant()
            if ($actualPySha -ne $expectedPySha) { throw "Python installer SHA-256 mismatch." }
            Log "Python installer SHA-256 OK"
        }

        Install-PythonFull -InstallerPath $pyInstaller -TargetDir $pythonDir
        $installedPy = Get-PythonVersion $pythonExe
        $tkOk = Test-Tkinter $pythonExe
        if ($installedPy -ne $expectedPy) { throw "Python verification failed. Expected $expectedPy, got $installedPy" }
        if (-not $tkOk) { throw "Python installed, but tkinter verification failed. Embedded fallback is forbidden." }
        Action "PYTHON" "OK" "Version=$installedPy tkinter=True"
    } else {
        Action "PYTHON" "SKIP" "Already healthy. Version=$installedPy tkinter=True"
    }

    $script:Status.components.python = [ordered]@{
        status = "ok"; action = $pythonAction; expected_version = $expectedPy; installed_version = $installedPy; tkinter = $tkOk; path = $pythonExe
    }

    # ---------------- Chrome ----------------
    $chromeExe = Find-SystemChrome
    $installedChrome = Get-ChromeVersion $chromeExe
    $latestChrome = $null
    $chromeAction = "SKIP"
    $chromeVersionUrl = "https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions.json"
    try { if ($manifest.chrome.stable_version_url) { $chromeVersionUrl = [string]$manifest.chrome.stable_version_url } } catch {}
    try {
        $chromeInfo = Invoke-RestMethod -Uri ($chromeVersionUrl + "?nocache=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())")
        $latestChrome = [string]$chromeInfo.channels.Stable.version
        Log "Chrome installed=$installedChrome latestStable=$latestChrome"
    } catch {
        Log "Could not query latest Chrome version: $($_.Exception.Message)" "WARN"
    }

    $needChrome = (-not $chromeExe)
    if ($chromeExe -and $latestChrome -and $installedChrome) {
        if (Version-LessThan $installedChrome $latestChrome) { $needChrome = $true; $chromeAction = "UPDATE" }
    }
    if (-not $chromeExe) { $chromeAction = "INSTALL" }

    if ($needChrome) {
        if (-not $InstallChrome) { throw "Chrome requires install/update but InstallChrome is disabled." }
        $chromeExe = Install-GoogleChrome -DownloadsDir $downloads -InstallerUrl ([string]$manifest.chrome.google_chrome_installer_url) -Kind ([string]$manifest.chrome.google_chrome_installer_kind)
        if (-not $chromeExe) { throw "Google Chrome was not found after installation/update." }
        $installedChrome = Get-ChromeVersion $chromeExe
        Action "CHROME" "OK" "Version=$installedChrome Path=$chromeExe"
    } else {
        Action "CHROME" "SKIP" "Already present/current enough. Version=$installedChrome Path=$chromeExe"
    }

    $script:Status.components.chrome = [ordered]@{
        status = "ok"; action = $chromeAction; installed_version = $installedChrome; latest_known_version = $latestChrome; path = $chromeExe
    }

    # ---------------- Chrome profile ----------------
    if ($CreateChromeProfile) {
        if (Test-Path $profile) {
            Action "PROFILE" "SKIP" "Preserving existing Chrome profile: $profile"
            $profileAction = "SKIP"
        } else {
            New-Item -ItemType Directory -Force -Path $profile | Out-Null
            Action "PROFILE" "CREATE" "Created Chrome profile: $profile"
            $profileAction = "CREATE"
        }
    }
    $script:Status.components.chrome_profile = [ordered]@{ status = "ok"; action = $profileAction; path = $profile; exists = (Test-Path $profile) }

    # ---------------- Control Center ----------------
    $expectedCc = [string]$manifest.control_center.version
    $configPath = Join-Path $configDir "platform.json"
    $installedCc = $null
    if (Test-Path $configPath) {
        try { $installedCc = [string]((Get-Content -Raw -Encoding UTF8 $configPath | ConvertFrom-Json).control_center_version) } catch {}
    }
    $ccGui = Join-Path $Root "control_center\gui.py"
    $ccRouter = Join-Path $Root "core\router.py"
    $ccHealthy = (Test-Path $ccGui) -and (Test-Path $ccRouter)
    $needCc = (-not $ccHealthy) -or ($installedCc -ne $expectedCc)
    $ccAction = "SKIP"

    if ($needCc) {
        if (-not $InstallControlCenter) { throw "Control Center requires install/update but InstallControlCenter is disabled." }
        if (-not $ccHealthy) { $ccAction = "INSTALL_REPAIR" } else { $ccAction = "UPDATE" }
        Action "CONTROL_CENTER" $ccAction "Expected=$expectedCc Installed=$installedCc Healthy=$ccHealthy"

        $pkg = Join-Path $downloads "ControlCenter-$expectedCc.zip"
        $pkgUrl = PackageUrl $ManifestUrl $manifest.control_center
        $downloadCc = $true
        if (Test-Path $pkg) {
            $downloadCc = $false
            if ($manifest.control_center.sha256) {
                $downloadCc = ((Sha $pkg) -ne ([string]$manifest.control_center.sha256).ToLowerInvariant())
            }
        }
        if ($downloadCc) { Download $pkgUrl $pkg }
        if ($manifest.control_center.sha256) {
            $actualCc = Sha $pkg
            $expectedCcSha = ([string]$manifest.control_center.sha256).ToLowerInvariant()
            if ($actualCc -ne $expectedCcSha) { throw "Control Center package SHA-256 mismatch." }
            Log "Control Center package SHA-256 OK"
        }

        $stage = Join-Path $bootstrap "control_stage"
        Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        Expand-Archive -Path $pkg -DestinationPath $stage -Force

        foreach ($name in @('control_center','core','commands')) {
            $src = Join-Path $stage $name
            $dst = Join-Path $Root $name
            if (-not (Test-Path $src)) { throw "Control Center package missing required folder: $name" }
            Remove-Item -Recurse -Force $dst -ErrorAction SilentlyContinue
            Copy-Item -Recurse -Force $src $dst
            Log "Installed program folder: $name"
        }

        $automationSrc = Join-Path $stage "automation.cmd"
        if (Test-Path $automationSrc) { Copy-Item -Force $automationSrc (Join-Path $Root 'automation.cmd') }
        $sharedSrc = Join-Path $stage "data\shared_values.json"
        $sharedDst = Join-Path $Root "data\shared_values.json"
        if ((Test-Path $sharedSrc) -and -not (Test-Path $sharedDst)) { Copy-Item -Force $sharedSrc $sharedDst }
        $exampleSrc = Join-Path $stage "modules\example_registration"
        $exampleDst = Join-Path $Root "modules\example_registration"
        if ((Test-Path $exampleSrc) -and -not (Test-Path $exampleDst)) { Copy-Item -Recurse -Force $exampleSrc $exampleDst }
        Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue

        $ccHealthy = (Test-Path $ccGui) -and (Test-Path $ccRouter)
        if (-not $ccHealthy) { throw "Control Center files are incomplete after extraction." }
        $installedCc = $expectedCc
        Action "CONTROL_CENTER" "OK" "Version=$installedCc"
    } else {
        Action "CONTROL_CENTER" "SKIP" "Already current and healthy. Version=$installedCc"
    }

    $script:Status.components.control_center = [ordered]@{
        status = "ok"; action = $ccAction; expected_version = $expectedCc; installed_version = $installedCc; gui = $ccGui; healthy = $ccHealthy
    }

    # ---------------- Refresh launchers and installer helpers ----------------
    Action "LAUNCHERS" "REFRESH" "Downloading latest launcher scripts from GitHub"
    $rootScripts = @('START_CHROME_DEBUG.cmd','START_CONTROL_CENTER.cmd','UPDATE_PLATFORM.cmd')
    $installerScripts = @('BOOTSTRAP_RUNNER.ps1','START_PLATFORM_INSTALLER.ps1','INSTALLER_CORE.ps1','START_INSTALLER_GUI.cmd','REPAIR_PYTHON_RUNTIME.ps1','INSTALL_AutomationPlatform.ps1')
    foreach ($name in $rootScripts) {
        Download ($rawBase + $name) (Join-Path $Root $name)
        Log "Deployed root launcher: $name"
    }
    foreach ($name in $installerScripts) {
        Download ($rawBase + $name) (Join-Path $installerDir $name)
        Log "Deployed installer helper: $name"
    }

    $rootBat = Join-Path $Root "INSTALL_AutomationPlatform.bat"
    if (-not (Test-Path $rootBat)) {
        Download ($rawBase + 'INSTALL_AutomationPlatform.bat') $rootBat
        Log "Deployed stable universal BAT to platform root"
    } else {
        Log "Universal BAT already exists; it remains a stable stub and always downloads latest BOOTSTRAP_RUNNER.ps1"
    }

    # ---------------- Config ----------------
    $debugPort = 9222
    $cdpHost = "127.0.0.1"
    try { $debugPort = [int]$manifest.defaults.debug_port } catch {}
    try { if ($manifest.defaults.cdp_host) { $cdpHost = [string]$manifest.defaults.cdp_host } } catch {}

    $config = [ordered]@{
        schema_version = 2
        platform_api = [int]$manifest.platform_api
        installed_at = (Get-Date).ToString("o")
        root = $Root
        manifest_url = $ManifestUrl
        manifest_schema_version = [int]$manifest.schema_version
        installer_core_version = $CoreVersion
        control_center_version = $expectedCc
        python_version = $installedPy
        python_exe = $pythonExe
        chrome_version = $installedChrome
        chrome_exe = $chromeExe
        chrome_source = "system"
        chrome_profile = $profile
        cdp_host = $cdpHost
        debug_port = $debugPort
    }
    $config | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $configPath
    Log "Wrote config: $configPath"

    # ---------------- Final health check ----------------
    $finalPython = Get-PythonVersion $pythonExe
    $finalTk = Test-Tkinter $pythonExe
    $finalChrome = Find-SystemChrome
    $finalCc = (Test-Path $ccGui) -and (Test-Path $ccRouter)
    $finalLaunchers = (Test-Path (Join-Path $Root 'START_CONTROL_CENTER.cmd')) -and (Test-Path (Join-Path $Root 'UPDATE_PLATFORM.cmd'))

    if ($finalPython -ne $expectedPy) { throw "FINAL CHECK: Python version mismatch: $finalPython" }
    if (-not $finalTk) { throw "FINAL CHECK: tkinter is unavailable." }
    if (-not $finalChrome) { throw "FINAL CHECK: Google Chrome is unavailable." }
    if (-not (Test-Path $profile)) { throw "FINAL CHECK: Chrome profile directory is missing." }
    if (-not $finalCc) { throw "FINAL CHECK: Control Center is incomplete." }
    if (-not $finalLaunchers) { throw "FINAL CHECK: launcher files are missing." }

    $script:Status.components.launchers = [ordered]@{ status = "ok"; action = "REFRESH"; control_center = (Join-Path $Root 'START_CONTROL_CENTER.cmd'); update = (Join-Path $Root 'UPDATE_PLATFORM.cmd') }
    $script:Status.overall_status = "ok"
    Save-Status

    Log "============================================================"
    Log "SUMMARY: SUCCESS"
    Log "Python        : $finalPython / tkinter=True / action=$pythonAction"
    Log "Chrome        : $installedChrome / action=$chromeAction"
    Log "Chrome Profile: $profile / action=$profileAction"
    Log "Control Center: $installedCc / action=$ccAction"
    Log "Installer Core: $CoreVersion"
    Log "============================================================"
    exit 0
}
catch {
    $script:Status.overall_status = "failed"
    $script:Status.error = $_.Exception.Message
    try { Save-Status } catch {}
    try { Log "FATAL: $($_.Exception.Message)" "ERROR" } catch { Write-Host $_.Exception.Message }
    try { Log $_.ScriptStackTrace "ERROR" } catch {}
    Write-Error $_.Exception.Message
    exit 1
}
