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
$bootstrapDir = Join-Path $Root "_bootstrap"
$downloadsDir = Join-Path $bootstrapDir "downloads"
$runtimeDir = Join-Path $Root "runtime"
$targetDir = Join-Path $runtimeDir "python"
$targetExe = Join-Path $targetDir "python.exe"
$tempStage = Join-Path $bootstrapDir "python_runtime_stage"
$backupDir = Join-Path $runtimeDir "python_previous"

New-Item -ItemType Directory -Force -Path $Root,$logDir,$bootstrapDir,$downloadsDir,$runtimeDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $logDir "python_runtime_$stamp.log"
$latestLog = Join-Path $logDir "latest_python_runtime.log"
"=== AutomationPlatform Python Runtime Manager $ManagerVersion ===" | Set-Content -Encoding UTF8 $logFile

function Log([string]$Text,[string]$Level="INFO") {
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$Level,$Text
    Write-Host $line
    Add-Content -Encoding UTF8 -Path $logFile -Value $line
}

function Download([string]$Url,[string]$Dest) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dest) | Out-Null
    Log "DOWNLOAD $Url"
    Log "        -> $Dest"
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Dest
    if (-not (Test-Path $Dest)) { throw "Download failed: $Url" }
    Log ("DOWNLOADED {0} bytes" -f (Get-Item $Dest).Length)
}

function Sha([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

function Get-PythonVersion([string]$Exe) {
    if (-not (Test-Path $Exe)) { return $null }
    try {
        $v = & $Exe -c "import sys; print('.'.join(map(str,sys.version_info[:3])))" 2>$null
        if ($LASTEXITCODE -eq 0 -and $v) { return ([string]$v).Trim() }
    } catch {}
    return $null
}

function Test-Tkinter([string]$Exe) {
    if (-not (Test-Path $Exe)) { return $false }
    try {
        & $Exe -c "import tkinter; print(tkinter.TkVersion)" *> $null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

function Test-Pip([string]$Exe) {
    if (-not (Test-Path $Exe)) { return $false }
    try {
        & $Exe -m pip --version *> $null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

function Ensure-Pip([string]$Exe) {
    if (Test-Pip $Exe) { return $true }
    Log "pip not available; trying ensurepip" "WARN"
    try {
        & $Exe -m ensurepip --upgrade 2>&1 | ForEach-Object { Log ("[ensurepip] " + [string]$_) }
        if ($LASTEXITCODE -ne 0) { Log "ensurepip exit code=$LASTEXITCODE" "WARN" }
    } catch {
        Log "ensurepip failed: $($_.Exception.Message)" "WARN"
    }
    return (Test-Pip $Exe)
}

function Test-Runtime([string]$Dir,[string]$ExpectedVersion,[bool]$RequireTk,[bool]$RequirePip) {
    $exe = Join-Path $Dir "python.exe"
    $version = Get-PythonVersion $exe
    $tk = Test-Tkinter $exe
    $pip = Test-Pip $exe
    if ($RequirePip -and -not $pip -and $version) {
        $pip = Ensure-Pip $exe
    }
    return [ordered]@{
        exe = $exe
        exists = (Test-Path $exe)
        version = $version
        tkinter = $tk
        pip = $pip
        healthy = (($version -eq $ExpectedVersion) -and ((-not $RequireTk) -or $tk) -and ((-not $RequirePip) -or $pip))
    }
}

try {
    Log "Root=$Root"
    Log "Manifest=$ManifestUrl"

    $manifest = Invoke-RestMethod -Uri ($ManifestUrl + "?nocache=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())")
    $expected = [string]$manifest.python.version
    $runtimeUrl = [string]$manifest.python.runtime_url
    $runtimeSha = ([string]$manifest.python.runtime_sha256).ToLowerInvariant()
    $requireTk = [bool]$manifest.python.require_tkinter
    $requirePip = $true
    try { $requirePip = [bool]$manifest.python.require_pip } catch {}

    if (-not $expected) { throw "Manifest python.version is empty." }
    if (-not $runtimeUrl) { throw "Manifest python.runtime_url is empty." }
    if (-not $runtimeSha) { throw "Manifest python.runtime_sha256 is empty." }

    Log "Expected Python=$expected; tkinter=$requireTk; pip=$requirePip"
    Log "Runtime strategy=official PythonCore ZIP / application-local extraction"

    $current = Test-Runtime -Dir $targetDir -ExpectedVersion $expected -RequireTk $requireTk -RequirePip $requirePip
    if ($current.healthy) {
        Log "[PYTHON][SKIP] Existing application-local runtime is healthy. Version=$($current.version) tkinter=$($current.tkinter) pip=$($current.pip)"
        Copy-Item -Force $logFile $latestLog
        exit 0
    }

    $action = if (-not $current.exists) { "INSTALL" } elseif ($current.version -ne $expected) { "UPDATE" } else { "REPAIR" }
    Log "[PYTHON][$action] Current version=$($current.version) tkinter=$($current.tkinter) pip=$($current.pip)"

    $zip = Join-Path $downloadsDir "python-$expected-pythoncore-amd64.zip"
    $needDownload = $true
    if (Test-Path $zip) {
        $cachedSha = Sha $zip
        if ($cachedSha -eq $runtimeSha) {
            $needDownload = $false
            Log "Using cached Python runtime ZIP; SHA-256 already valid."
        } else {
            Log "Cached runtime SHA-256 mismatch; deleting cache." "WARN"
            Remove-Item -Force $zip -ErrorAction SilentlyContinue
        }
    }
    if ($needDownload) { Download $runtimeUrl $zip }

    $actualSha = Sha $zip
    if ($actualSha -ne $runtimeSha) {
        Remove-Item -Force $zip -ErrorAction SilentlyContinue
        throw "Python runtime ZIP SHA-256 mismatch. Expected=$runtimeSha Actual=$actualSha"
    }
    Log "Python runtime ZIP SHA-256 OK: $actualSha"

    Remove-Item -Recurse -Force $tempStage -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $tempStage | Out-Null
    Log "Extracting candidate runtime to staging: $tempStage"
    Expand-Archive -Path $zip -DestinationPath $tempStage -Force

    $candidate = Test-Runtime -Dir $tempStage -ExpectedVersion $expected -RequireTk $requireTk -RequirePip $requirePip
    Log "Candidate verification: exists=$($candidate.exists) version=$($candidate.version) tkinter=$($candidate.tkinter) pip=$($candidate.pip) healthy=$($candidate.healthy)"
    if (-not $candidate.healthy) {
        $names = @()
        foreach ($rel in @('python.exe','pythonw.exe','Lib\tkinter\__init__.py','DLLs\_tkinter.pyd','tcl')) {
            $p = Join-Path $tempStage $rel
            $names += "$rel=$(Test-Path $p)"
        }
        Log ("Candidate diagnostic: " + ($names -join '; ')) "ERROR"
        throw "Downloaded PythonCore runtime failed staging verification. Existing runtime was NOT replaced."
    }

    Remove-Item -Recurse -Force $backupDir -ErrorAction SilentlyContinue
    if (Test-Path $targetDir) {
        Log "Moving previous runtime to backup: $backupDir"
        Move-Item -Force $targetDir $backupDir
    }

    try {
        Log "Activating verified runtime: $targetDir"
        Move-Item -Force $tempStage $targetDir
    } catch {
        if ((Test-Path $backupDir) -and -not (Test-Path $targetDir)) {
            Move-Item -Force $backupDir $targetDir
        }
        throw
    }

    $final = Test-Runtime -Dir $targetDir -ExpectedVersion $expected -RequireTk $requireTk -RequirePip $requirePip
    Log "Final verification: version=$($final.version) tkinter=$($final.tkinter) pip=$($final.pip) healthy=$($final.healthy)"
    if (-not $final.healthy) {
        Log "Activated runtime failed final verification. Rolling back." "ERROR"
        Remove-Item -Recurse -Force $targetDir -ErrorAction SilentlyContinue
        if (Test-Path $backupDir) { Move-Item -Force $backupDir $targetDir }
        throw "Final Python runtime verification failed; previous runtime restored when available."
    }

    Remove-Item -Recurse -Force $backupDir -ErrorAction SilentlyContinue
    Log "[PYTHON][OK] Application-local Python ready at $targetExe"
    Log "No Python PATH, registry, Start Menu, launcher or system-wide installation was created by this runtime manager."
    Copy-Item -Force $logFile $latestLog
    exit 0
}
catch {
    Log "FATAL: $($_.Exception.Message)" "ERROR"
    try { Log $_.ScriptStackTrace "ERROR" } catch {}
    try { Copy-Item -Force $logFile $latestLog } catch {}
    exit 1
}
