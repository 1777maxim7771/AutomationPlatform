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

function Step([string]$Text) { Log "[STEP] $Text" }

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

function Find-PythonExe([string]$SearchRoot) {
    if (-not (Test-Path $SearchRoot)) { return $null }
    $direct = Join-Path $SearchRoot "python.exe"
    if (Test-Path $direct) { return $direct }
    $found = Get-ChildItem -Path $SearchRoot -Filter "python.exe" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\Lib\\|\\Scripts\\' } |
        Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
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

function Install-PythonFull([string]$InstallerPath, [string]$TargetDir) {
    if (Test-Path $TargetDir) {
        $items = Get-ChildItem $TargetDir -Force -ErrorAction SilentlyContinue
        if (-not $items) { Remove-Item -Force $TargetDir -ErrorAction SilentlyContinue }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $TargetDir) | Out-Null
    $arg = "/quiet InstallAllUsers=0 TargetDir=`"$TargetDir`" PrependPath=0 AppendPath=0 Include_launcher=0 InstallLauncherAllUsers=0 Include_test=0 Include_doc=0 Shortcuts=0 AssociateFiles=0 Include_pip=1 Include_tcltk=1 Include_tools=1"
    Log "Python silent args: $arg"
    $p = Start-Process -FilePath $InstallerPath -ArgumentList $arg -Wait -PassThru
    Log "Python installer exit code: $($p.ExitCode)"
    return $p.ExitCode
}

function Install-PythonEmbed([string]$Version, [string]$TargetDir, [string]$DownloadsDir, [string]$EmbedUrl, [string]$GetPipUrl) {
    if (-not $EmbedUrl) { $EmbedUrl = "https://www.python.org/ftp/python/$Version/python-$Version-embed-amd64.zip" }
    if (-not $GetPipUrl) { $GetPipUrl = "https://bootstrap.pypa.io/get-pip.py" }
    $zip = Join-Path $DownloadsDir "python-$Version-embed-amd64.zip"
    if (-not (Test-Path $zip)) { Download $EmbedUrl $zip } else { Log "Reusing embed package: $zip" }

    if (Test-Path $TargetDir) { Remove-Item -Recurse -Force $TargetDir -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    Expand-Archive -Path $zip -DestinationPath $TargetDir -Force

    $pth = Get-ChildItem $TargetDir -Filter "python*._pth" | Select-Object -First 1
    if ($pth) {
        $content = Get-Content $pth.FullName
        $newContent = @()
        foreach ($line in $content) {
            if ($line -match '^#\s*import site') { $newContent += 'import site' } else { $newContent += $line }
        }
        if ($newContent -notcontains 'import site') { $newContent += 'import site' }
        Set-Content -Path $pth.FullName -Value $newContent -Encoding ASCII
        Log "Enabled import site in $($pth.Name)"
    }

    $getPip = Join-Path $DownloadsDir "get-pip.py"
    try {
        if (-not (Test-Path $getPip)) { Download $GetPipUrl $getPip }
        $py = Join-Path $TargetDir "python.exe"
        if (Test-Path $py) {
            Log "Installing pip into embeddable Python..."
            & $py $getPip --no-warn-script-location 2>&1 | ForEach-Object { Log "  $_" }
        }
    } catch { Log "WARN: get-pip failed: $($_.Exception.Message)" }

    return (Find-PythonExe $TargetDir)
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

    $pyMethod = "embed_first"
    try { if ($manifest.python.method) { $pyMethod = [string]$manifest.python.method } } catch {}
    Log "Python method: $pyMethod"

    $preferSystemChrome = $true
    try { if ($null -ne $manifest.chrome.prefer_system_chrome) { $preferSystemChrome = [bool]$manifest.chrome.prefer_system_chrome } } catch {}
    $installCft = $true
    try { if ($null -ne $manifest.chrome.install_cft_if_missing) { $installCft = [bool]$manifest.chrome.install_cft_if_missing } } catch {}

    $bootstrap    = Join-Path $Root "_bootstrap"
    $downloads    = Join-Path $bootstrap "downloads"
    $runtime      = Join-Path $Root "runtime"
    $pythonDir    = Join-Path $runtime "python"
    $chromeRoot   = Join-Path $runtime "chrome"
    $browser      = Join-Path $Root "browser"
    $profile      = Join-Path $browser "Chrome_Profile"
    $configDir    = Join-Path $Root "config"
    $installerDir = Join-Path $Root "installer"

    foreach ($d in @(
        $Root,$bootstrap,$downloads,$runtime,$chromeRoot,$browser,$configDir,$installerDir,
        (Join-Path $Root "modules"),(Join-Path $Root "data"),(Join-Path $Root "jobs"),
        (Join-Path $Root "logs"),(Join-Path $Root "_update")
    )) { New-Item -ItemType Directory -Force -Path $d | Out-Null }

    $pythonExe = Find-PythonExe $pythonDir

    if ($InstallPython) {
        if ($pythonExe) {
            Step "Local Python already present: $pythonExe"
        } else {
            Step "Installing local Python $($manifest.python.version) [method=$pyMethod]"
            $ver = [string]$manifest.python.version
            $embedUrl = $null; $getPipUrl = $null
            try { $embedUrl = [string]$manifest.python.embed_url } catch {}
            try { $getPipUrl = [string]$manifest.python.get_pip_url } catch {}

            if ($pyMethod -eq "embed_first" -or $pyMethod -eq "embed") {
                try { $pythonExe = Install-PythonEmbed -Version $ver -TargetDir $pythonDir -DownloadsDir $downloads -EmbedUrl $embedUrl -GetPipUrl $getPipUrl }
                catch { Log "Embed install failed: $($_.Exception.Message)" }
            }
            if (-not $pythonExe -and $pyMethod -ne "embed") {
                $pyInstaller = Join-Path $downloads "python-$ver-amd64.exe"
                try {
                    if (-not (Test-Path $pyInstaller)) { Download ([string]$manifest.python.installer_url) $pyInstaller }
                    $null = Install-PythonFull -InstallerPath $pyInstaller -TargetDir $pythonDir
                    Start-Sleep -Seconds 2
                    $pythonExe = Find-PythonExe $pythonDir
                } catch { Log "Full installer failed: $($_.Exception.Message)" }
            }
            if ($pythonExe) {
                Log "Python OK: $pythonExe"
                try { Log ("Python version: {0}" -f (& $pythonExe --version 2>&1)) } catch {}
            } else { Log "WARNING: Python was NOT installed." }
        }
    }

    # ---- Chrome resolution ----
    $systemChrome = Find-SystemChrome
    $cftChrome = Join-Path $chromeRoot "chrome-win64\chrome.exe"
    $chromeExe = ""
    $chromeSource = ""

    if ($preferSystemChrome -and $systemChrome) {
        $chromeExe = $systemChrome
        $chromeSource = "system"
        Log "System Google Chrome found: $systemChrome"
    }

    # Always try to keep CfT available as offline/automation fallback when requested
    if ($InstallChrome -or $installCft) {
        Step "Ensure Chrome for Testing is available (fallback binary)"
        try {
            $cft = Invoke-RestMethod -Uri ([string]$manifest.chrome.cft_json_url)
            $stable = $cft.channels.Stable
            $platform = [string]$manifest.chrome.platform
            $download = $stable.downloads.chrome | Where-Object { $_.platform -eq $platform } | Select-Object -First 1
            if (-not $download) { throw "CfT package not found for $platform" }

            $versionFile = Join-Path $chromeRoot "VERSION.txt"
            $installed = ""
            if (Test-Path $versionFile) { $installed = (Get-Content -Raw $versionFile).Trim() }
            $need = ($installed -ne [string]$stable.version) -or (-not (Test-Path $cftChrome))

            if ($need) {
                $zip = Join-Path $downloads "chrome-$($stable.version).zip"
                if (-not (Test-Path $zip)) { Download ([string]$download.url) $zip } else { Log "Reusing CfT zip" }
                $stage = Join-Path $bootstrap "chrome_stage"
                Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
                New-Item -ItemType Directory -Force -Path $stage | Out-Null
                Expand-Archive -Path $zip -DestinationPath $stage -Force
                Get-ChildItem $chromeRoot -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                $srcChrome = Join-Path $stage "chrome-win64"
                if (-not (Test-Path $srcChrome)) {
                    $srcChrome = Get-ChildItem $stage -Directory | Select-Object -First 1 | ForEach-Object { $_.FullName }
                }
                Copy-Item -Recurse -Force $srcChrome (Join-Path $chromeRoot "chrome-win64")
                Set-Content -Encoding ASCII $versionFile ([string]$stable.version)
                Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
            }
            if (Test-Path $cftChrome) { Log "Chrome for Testing OK: $cftChrome" }
        } catch {
            Log "CfT install failed: $($_.Exception.Message)"
        }
    }

    if (-not $chromeExe) {
        if (Test-Path $cftChrome) {
            $chromeExe = $cftChrome
            $chromeSource = "cft"
            Log "Using Chrome for Testing (no system Chrome)."
        } else {
            Log "WARNING: No Chrome binary available. Install Google Chrome or re-run installer."
        }
    }

    if ($CreateChromeProfile) {
        Step "Platform Chrome profile (sessions/cookies for automation)"
        New-Item -ItemType Directory -Force -Path $profile | Out-Null
        Log "Profile dir: $profile"
        Log "NOTE: Log in to ChatGPT once via START_CHROME_DEBUG.cmd - session is stored here."
    }

    # ---- Control Center ----
    if ($InstallControlCenter) {
        Step "Installing/updating Control Center $($manifest.control_center.version)"
        $pkg = Join-Path $downloads "ControlCenter-$($manifest.control_center.version).zip"
        $url = PackageUrl $ManifestUrl $manifest.control_center
        if (-not (Test-Path $pkg)) { Download $url $pkg } else { Log "Reusing Control Center package" }

        if ($manifest.control_center.sha256) {
            $actual = Sha $pkg
            $expect = ([string]$manifest.control_center.sha256).ToLowerInvariant()
            if ($actual -ne $expect) {
                Log "SHA mismatch (continuing) expected=$expect actual=$actual"
            } else { Log "Control Center SHA OK" }
        }

        $stage = Join-Path $bootstrap "control_stage"
        Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        Expand-Archive -Path $pkg -DestinationPath $stage -Force

        foreach ($name in @("control_center","core","commands")) {
            $src = Join-Path $stage $name; $dst = Join-Path $Root $name
            if (Test-Path $src) {
                Remove-Item -Recurse -Force $dst -ErrorAction SilentlyContinue
                Copy-Item -Recurse -Force $src $dst
                Log "Copied $name"
            }
        }
        foreach ($name in @("START_CONTROL_CENTER.cmd","automation.cmd")) {
            $src = Join-Path $stage $name
            if (Test-Path $src) { Copy-Item -Force $src (Join-Path $Root $name); Log "Copied $name" }
        }
        $svSrc = Join-Path $stage "data\shared_values.json"
        $svDst = Join-Path $Root "data\shared_values.json"
        if ((Test-Path $svSrc) -and -not (Test-Path $svDst)) { Copy-Item -Force $svSrc $svDst }
        $modSrc = Join-Path $stage "modules\example_registration"
        $modDst = Join-Path $Root "modules\example_registration"
        if ((Test-Path $modSrc) -and -not (Test-Path $modDst)) { Copy-Item -Recurse -Force $modSrc $modDst }
        Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
    }

    if (-not $pythonExe) {
        $pythonExe = Find-PythonExe $pythonDir
        if (-not $pythonExe) { $pythonExe = Join-Path $pythonDir "python.exe" }
    }

    $debugPort = 9222
    $cdpHost = "127.0.0.1"
    try { $debugPort = [int]$manifest.defaults.debug_port } catch {}
    try { if ($manifest.chrome.debug_port) { $debugPort = [int]$manifest.chrome.debug_port } } catch {}
    try { if ($manifest.defaults.cdp_host) { $cdpHost = [string]$manifest.defaults.cdp_host } } catch {}

    $config = [ordered]@{
        schema_version = 1
        platform_api = 1
        root = $Root
        manifest_url = $ManifestUrl
        control_center_version = [string]$manifest.control_center.version
        python_exe = $pythonExe
        chrome_exe = $chromeExe
        chrome_source = $chromeSource
        chrome_cft_exe = $(if (Test-Path $cftChrome) { $cftChrome } else { "" })
        chrome_profile = $profile
        cdp_host = $cdpHost
        debug_port = $debugPort
    }
    $configPath = Join-Path $configDir "platform.json"
    $config | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $configPath
    Log "Wrote $configPath"

    Step "Refreshing helper scripts"
    foreach ($name in @("START_PLATFORM_INSTALLER.ps1","INSTALLER_CORE.ps1","START_INSTALLER_GUI.cmd","INSTALL_AutomationPlatform.bat","INSTALL_AutomationPlatform.ps1","START_CHROME_DEBUG.cmd")) {
        try {
            $dest = if ($name -eq "START_CHROME_DEBUG.cmd") { Join-Path $Root $name } else { Join-Path $installerDir $name }
            if ($name -eq "START_CHROME_DEBUG.cmd") {
                Download ($rawBase + $name) (Join-Path $Root $name)
            } else {
                Download ($rawBase + $name) (Join-Path $installerDir $name)
            }
        } catch { Log "WARN: could not refresh $name" }
    }

    $rootUpdateCmd = "@echo off`r`nsetlocal`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File ""%~dp0installer\START_PLATFORM_INSTALLER.ps1"" -DefaultRoot ""%~dp0""`r`nendlocal`r`n"
    Set-Content -Encoding ASCII -Path (Join-Path $Root "UPDATE_PLATFORM.cmd") -Value $rootUpdateCmd

    Step "Done"
    Log "Root           : $Root"
    Log "Python         : $pythonExe (exists=$(Test-Path ([string]$pythonExe)))"
    Log "Chrome         : $chromeExe (source=$chromeSource)"
    Log "Chrome Profile : $profile"
    Log "CDP            : ${cdpHost}:$debugPort"
    Log "Start Chrome   : $(Join-Path $Root 'START_CHROME_DEBUG.cmd')"
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
