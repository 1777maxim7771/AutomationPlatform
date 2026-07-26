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

function Step([string]$Text) {
    Write-Host "[AutomationPlatform] $Text" -ForegroundColor Cyan
}

function Download([string]$Url, [string]$Dest) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dest) | Out-Null
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Dest
}

function Sha([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

function PackageUrl([string]$ManifestUrlValue, $Item) {
    if ($Item.package_url) { return [string]$Item.package_url }
    if (-not $Item.package_path) { throw "Manifest item has no package_url/package_path." }
    $base = [Uri]$ManifestUrlValue
    return (New-Object System.Uri($base, ([string]$Item.package_path).Replace("\","/"))).AbsoluteUri
}

function RawBase([string]$ManifestUrlValue) {
    $u = [Uri]$ManifestUrlValue
    $path = $u.AbsolutePath
    $idx = $path.LastIndexOf('/')
    if ($idx -lt 0) { throw "Cannot resolve repository raw base from Manifest URL." }
    $basePath = $path.Substring(0, $idx + 1)
    return "$($u.Scheme)://$($u.Host)$basePath"
}

Step "Loading manifest"
$manifest = Invoke-RestMethod -Uri $ManifestUrl
$rawBase = RawBase $ManifestUrl

$bootstrap = Join-Path $Root "_bootstrap"
$downloads = Join-Path $bootstrap "downloads"
$runtime = Join-Path $Root "runtime"
$pythonDir = Join-Path $runtime "python"
$chromeRoot = Join-Path $runtime "chrome"
$browser = Join-Path $Root "browser"
$profile = Join-Path $browser "Chrome_Profile"
$configDir = Join-Path $Root "config"
$installerDir = Join-Path $Root "installer"

foreach ($d in @(
    $Root,$bootstrap,$downloads,$runtime,$chromeRoot,$browser,$configDir,$installerDir,
    (Join-Path $Root "modules"),(Join-Path $Root "data"),(Join-Path $Root "jobs"),
    (Join-Path $Root "logs"),(Join-Path $Root "_update")
)) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

$pythonExe = Join-Path $pythonDir "python.exe"

if ($InstallPython) {
    if (-not (Test-Path $pythonExe)) {
        Step "Installing local Python $($manifest.python.version)"
        $pyInstaller = Join-Path $downloads "python-$($manifest.python.version)-amd64.exe"
        Download ([string]$manifest.python.installer_url) $pyInstaller
        if ($manifest.python.sha256) {
            if ((Sha $pyInstaller) -ne ([string]$manifest.python.sha256).ToLowerInvariant()) {
                Remove-Item -Force $pyInstaller -ErrorAction SilentlyContinue
                throw "Python SHA-256 mismatch."
            }
        }
        $args = @(
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
        $p = Start-Process -FilePath $pyInstaller -ArgumentList $args -Wait -PassThru
        if ($p.ExitCode -ne 0 -or -not (Test-Path $pythonExe)) {
            throw "Python installation failed. ExitCode=$($p.ExitCode)"
        }
    } else {
        Step "Local Python already installed"
    }
}

$chromeExe = ""
if ($InstallChrome) {
    Step "Installing/updating Chrome for Testing Stable"
    $cft = Invoke-RestMethod -Uri ([string]$manifest.chrome.cft_json_url)
    $stable = $cft.channels.Stable
    $platform = [string]$manifest.chrome.platform
    $download = $stable.downloads.chrome | Where-Object { $_.platform -eq $platform } | Select-Object -First 1
    if (-not $download) { throw "Chrome for Testing package not found." }

    $versionFile = Join-Path $chromeRoot "VERSION.txt"
    $installed = ""
    if (Test-Path $versionFile) { $installed = (Get-Content -Raw $versionFile).Trim() }

    if ($installed -ne [string]$stable.version) {
        $zip = Join-Path $downloads "chrome-$($stable.version).zip"
        Download ([string]$download.url) $zip
        $stage = Join-Path $bootstrap "chrome_stage"
        Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        Expand-Archive -Path $zip -DestinationPath $stage -Force
        Get-ChildItem $chromeRoot -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item -Recurse -Force (Join-Path $stage "chrome-win64") (Join-Path $chromeRoot "chrome-win64")
        Set-Content -Encoding ASCII $versionFile ([string]$stable.version)
        Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
    }
    $chromeExe = Join-Path $chromeRoot "chrome-win64\chrome.exe"
    if (-not (Test-Path $chromeExe)) { throw "Chrome executable not found after install." }
} else {
    $candidate = Join-Path $chromeRoot "chrome-win64\chrome.exe"
    if (Test-Path $candidate) { $chromeExe = $candidate }
}

if ($CreateChromeProfile) {
    Step "Creating/preserving Chrome Profile directory"
    New-Item -ItemType Directory -Force -Path $profile | Out-Null
}

if ($InstallControlCenter) {
    Step "Installing/updating Control Center $($manifest.control_center.version)"
    $pkg = Join-Path $downloads "ControlCenter-$($manifest.control_center.version).zip"

    if ([string]$manifest.control_center.encoding -eq "base64-parts") {
        if (-not $manifest.control_center.package_parts) {
            throw "Manifest has encoding=base64-parts but package_parts is empty."
        }
        $builder = New-Object System.Text.StringBuilder
        $partIndex = 0
        foreach ($part in $manifest.control_center.package_parts) {
            $partIndex++
            Step "Downloading Control Center package part $partIndex/$($manifest.control_center.package_parts.Count)"
            $partUrl = (New-Object System.Uri([Uri]$ManifestUrl, ([string]$part).Replace("\","/"))).AbsoluteUri
            $partFile = Join-Path $downloads ("control_center_part_{0:D2}.b64" -f $partIndex)
            Download $partUrl $partFile
            [void]$builder.Append(((Get-Content -Raw -Encoding UTF8 $partFile) -replace "\s", ""))
            Remove-Item -Force $partFile -ErrorAction SilentlyContinue
        }
        [IO.File]::WriteAllBytes($pkg, [Convert]::FromBase64String($builder.ToString()))
    } elseif ([string]$manifest.control_center.encoding -eq "base64") {
        $url = PackageUrl $ManifestUrl $manifest.control_center
        $encodedPkg = $pkg + ".b64"
        Download $url $encodedPkg
        $encodedText = (Get-Content -Raw -Encoding UTF8 $encodedPkg) -replace "\s", ""
        [IO.File]::WriteAllBytes($pkg, [Convert]::FromBase64String($encodedText))
        Remove-Item -Force $encodedPkg -ErrorAction SilentlyContinue
    } else {
        $url = PackageUrl $ManifestUrl $manifest.control_center
        Download $url $pkg
    }

    if ($manifest.control_center.sha256) {
        if ((Sha $pkg) -ne ([string]$manifest.control_center.sha256).ToLowerInvariant()) {
            Remove-Item -Force $pkg -ErrorAction SilentlyContinue
            throw "Control Center SHA-256 mismatch."
        }
    }

    $stage = Join-Path $bootstrap "control_stage"
    Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Expand-Archive -Path $pkg -DestinationPath $stage -Force

    foreach ($name in @("control_center","core","commands")) {
        $src = Join-Path $stage $name
        $dst = Join-Path $Root $name
        if (Test-Path $src) {
            Remove-Item -Recurse -Force $dst -ErrorAction SilentlyContinue
            Copy-Item -Recurse -Force $src $dst
        }
    }

    foreach ($name in @("START_CONTROL_CENTER.cmd","automation.cmd")) {
        $src = Join-Path $stage $name
        if (Test-Path $src) { Copy-Item -Force $src (Join-Path $Root $name) }
    }

    if (-not (Test-Path (Join-Path $Root "data\shared_values.json"))) {
        Copy-Item -Force (Join-Path $stage "data\shared_values.json") (Join-Path $Root "data\shared_values.json")
    }

    if (-not (Test-Path (Join-Path $Root "modules\example_registration"))) {
        Copy-Item -Recurse -Force (Join-Path $stage "modules\example_registration") (Join-Path $Root "modules\example_registration")
    }

    Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
}

if (-not $chromeExe) {
    $candidate = Join-Path $chromeRoot "chrome-win64\chrome.exe"
    if (Test-Path $candidate) { $chromeExe = $candidate }
}

$debugPort = [int]$manifest.defaults.debug_port
$config = [ordered]@{
    schema_version = 1
    platform_api = [int]$manifest.platform_api
    root = $Root
    manifest_url = $ManifestUrl
    control_center_version = [string]$manifest.control_center.version
    python_exe = $pythonExe
    chrome_exe = $chromeExe
    chrome_profile = $profile
    cdp_host = "127.0.0.1"
    debug_port = $debugPort
}
$config | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 (Join-Path $configDir "platform.json")

# Keep a local update launcher inside the installed platform.
Step "Installing local platform updater"
foreach ($name in @("START_PLATFORM_INSTALLER.ps1","INSTALLER_CORE.ps1","START_INSTALLER_GUI.cmd")) {
    try {
        Download ($rawBase + $name) (Join-Path $installerDir $name)
    } catch {
        Write-Warning "Could not refresh installer file $name : $($_.Exception.Message)"
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
Write-Host "Root          : $Root" -ForegroundColor Green
Write-Host "Python        : $pythonExe" -ForegroundColor Green
Write-Host "Chrome        : $chromeExe" -ForegroundColor Green
Write-Host "Chrome Profile: $profile" -ForegroundColor Green
Write-Host "Updater       : $(Join-Path $Root 'UPDATE_PLATFORM.cmd')" -ForegroundColor Green
