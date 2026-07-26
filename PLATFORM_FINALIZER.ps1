param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$ManifestUrl
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$FinalizerVersion = "2026.07.27.3"

$Root = $Root.Trim().Trim([char]0x22,[char]0x27).TrimEnd('\','/').Trim()
if (-not $Root) { throw "Root path is empty." }

$logDir = Join-Path $Root "logs"
$dataDir = Join-Path $Root "data"
$configDir = Join-Path $Root "config"
$installerDir = Join-Path $Root "installer"
$downloads = Join-Path $Root "_bootstrap\downloads"
$profile = Join-Path $Root "browser\Chrome_Profile"
foreach ($d in @($Root,$logDir,$dataDir,$configDir,$installerDir,$downloads,(Split-Path $profile -Parent),(Join-Path $Root 'modules'),(Join-Path $Root 'jobs'))) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $logDir "finalizer_$stamp.log"
$latestLog = Join-Path $logDir "latest_finalizer.log"
"=== AutomationPlatform Platform Finalizer $FinalizerVersion ===" | Set-Content -Encoding UTF8 $logFile

function Log([string]$Text,[string]$Level="INFO") {
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$Level,$Text
    Write-Host $line
    Add-Content -Encoding UTF8 -Path $logFile -Value $line
}
function Action([string]$Component,[string]$Action,[string]$Text) { Log "[$Component][$Action] $Text" }
function Sha([string]$Path) { return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant() }
function RawBase([string]$Url) {
    $u=[Uri]$Url; $idx=$u.AbsolutePath.LastIndexOf('/')
    if($idx -lt 0){throw "Cannot resolve repository raw base."}
    return "$($u.Scheme)://$($u.Host)$($u.AbsolutePath.Substring(0,$idx+1))"
}
function Download([string]$Url,[string]$Dest) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Dest -Parent) | Out-Null
    $sep=if($Url -match '\?'){'&'}else{'?'}
    $fetch=if($Url -match 'raw\.githubusercontent\.com'){"$Url$sep`nocache=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"}else{$Url}
    Log "DOWNLOAD $fetch"
    Invoke-WebRequest -UseBasicParsing -Uri $fetch -OutFile $Dest
    if(-not(Test-Path $Dest)){throw "Download failed: $Url"}
    Log ("DOWNLOADED {0} bytes -> {1}" -f (Get-Item $Dest).Length,$Dest)
}
function Find-Chrome {
    $c=@((Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),(Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe'))
    foreach($p in $c){if($p -and (Test-Path $p)){return $p}}
    return $null
}
function Version-Of([string]$Path){if($Path -and (Test-Path $Path)){try{return ([string](Get-Item $Path).VersionInfo.ProductVersion).Trim()}catch{}};return $null}
function Py-Version([string]$Exe){if(-not(Test-Path $Exe)){return $null};try{$v=& $Exe -c "import sys;print('.'.join(map(str,sys.version_info[:3])))" 2>$null;if($LASTEXITCODE -eq 0){return([string]$v).Trim()}}catch{};return $null}
function Test-Tk([string]$Exe){if(-not(Test-Path $Exe)){return $false};try{& $Exe -c "import tkinter" 2>$null;return($LASTEXITCODE -eq 0)}catch{return $false}}
function Test-Pip([string]$Exe){if(-not(Test-Path $Exe)){return $false};try{& $Exe -m pip --version 2>$null;return($LASTEXITCODE -eq 0)}catch{return $false}}

function Repair-ControlCenterGui([string]$GuiPath,[string]$PythonExe,[string]$ExpectedVersion) {
    if(-not(Test-Path $GuiPath)){throw "Control Center GUI is missing: $GuiPath"}
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $text = [IO.File]::ReadAllText($GuiPath,$utf8)
    $rx = [regex]::new('(?ms)^class\s+FXButton\b.*?(?=^class\s+|\z)')
    $m = $rx.Match($text)
    if(-not $m.Success){throw "FXButton class was not found in Control Center GUI."}

    $block = $m.Value
    $changed = $false
    # Tkinter itself owns widget._w (Tcl command path). The old visual button
    # accidentally reused _w for pixel width, turning commands into names such
    # as '195'. Only patch the FXButton block when that bad assignment exists.
    if($block -match 'self\._w\s*=\s*width') {
        $block = [regex]::Replace($block,'self\._w\b','self._fx_w')
        $changed = $true
        Action "CONTROL_CENTER" "PATCH" "FXButton width field self._w -> self._fx_w (protect Tkinter Tcl widget path)"
    }
    if($block -match 'self\._h\s*=\s*height') {
        $block = [regex]::Replace($block,'self\._h\b','self._fx_h')
        $changed = $true
        Action "CONTROL_CENTER" "PATCH" "FXButton height field self._h -> self._fx_h"
    }
    if($changed) {
        $text = $text.Substring(0,$m.Index) + $block + $text.Substring($m.Index+$m.Length)
    }
    # Keep the visible title/version aligned with the manifest build.
    if($ExpectedVersion) {
        $text = $text.Replace('v0.5.0',('v'+$ExpectedVersion))
        $text = $text.Replace('"0.5.0"',('"'+$ExpectedVersion+'"'))
        $text = $text.Replace("'0.5.0'",("'"+$ExpectedVersion+"'"))
    }
    [IO.File]::WriteAllText($GuiPath,$text,$utf8)

    $verify=[IO.File]::ReadAllText($GuiPath,$utf8)
    $vm=$rx.Match($verify)
    if(-not $vm.Success){throw "FXButton disappeared after GUI repair."}
    if($vm.Value -match 'self\._w\s*=\s*width'){throw "FXButton repair failed: Tkinter reserved self._w is still overwritten."}

    & $PythonExe -m py_compile $GuiPath 2>&1 | ForEach-Object { Log ("[py_compile] "+[string]$_) }
    if($LASTEXITCODE -ne 0){throw "Control Center gui.py failed Python syntax validation after repair."}
    Action "CONTROL_CENTER" "VALIDATE" "gui.py compiled successfully; FXButton Tkinter collision absent"
}

try {
    Log "Root=$Root"
    Log "Manifest=$ManifestUrl"
    $manifest=Invoke-RestMethod -Uri ($ManifestUrl+"?nocache=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())")
    $rawBase=RawBase $ManifestUrl

    $pythonExe=Join-Path $Root "runtime\python\python.exe"
    $pythonVersion=Py-Version $pythonExe
    $tk=Test-Tk $pythonExe
    $pip=Test-Pip $pythonExe
    if((-not $pythonVersion) -or (-not $tk) -or (-not $pip)){throw "Finalizer requires a healthy pre-verified Python runtime."}
    Action "PYTHON" "PREVERIFIED" "Version=$pythonVersion tkinter=$tk pip=$pip"

    $chromeExe=Find-Chrome
    if(-not $chromeExe){throw "Finalizer requires a healthy pre-verified Google Chrome installation."}
    $chromeVersion=Version-Of $chromeExe
    Action "CHROME" "PREVERIFIED" "Version=$chromeVersion Path=$chromeExe"

    if(Test-Path $profile){Action "PROFILE" "SKIP" "Preserving existing Chrome profile: $profile"}
    else{New-Item -ItemType Directory -Force -Path $profile|Out-Null;Action "PROFILE" "CREATE" "Created Chrome profile: $profile"}

    $expectedCc=[string]$manifest.control_center.version
    $configPath=Join-Path $configDir "platform.json"
    $installedCc=$null
    if(Test-Path $configPath){try{$installedCc=[string]((Get-Content -Raw -Encoding UTF8 $configPath|ConvertFrom-Json).control_center_version)}catch{}}
    $ccGui=Join-Path $Root "control_center\gui.py"
    $ccRouter=Join-Path $Root "core\router.py"
    $ccHealthy=(Test-Path $ccGui) -and (Test-Path $ccRouter)
    $needCc=(-not $ccHealthy) -or ($installedCc -ne $expectedCc)
    $ccAction="SKIP"

    if($needCc){
        $ccAction=if($ccHealthy){"UPDATE"}else{"INSTALL_REPAIR"}
        Action "CONTROL_CENTER" $ccAction "Expected=$expectedCc Installed=$installedCc Healthy=$ccHealthy"
        $pkg=Join-Path $downloads "ControlCenter-$expectedCc.zip"
        if(-not(Test-Path $pkg)){throw "Prepared Control Center package not found: $pkg"}
        $expectedSha=([string]$manifest.control_center.sha256).ToLowerInvariant()
        if($expectedSha){$actual=Sha $pkg;if($actual -ne $expectedSha){throw "Control Center package SHA-256 mismatch. Expected=$expectedSha Actual=$actual"};Log "Control Center package SHA-256 OK"}

        $stage=Join-Path $Root "_bootstrap\control_stage"
        Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $stage|Out-Null
        Expand-Archive -Path $pkg -DestinationPath $stage -Force
        foreach($name in @('control_center','core','commands')){
            $src=Join-Path $stage $name;$dst=Join-Path $Root $name
            if(-not(Test-Path $src)){throw "Control Center package missing required folder: $name"}
            Remove-Item -Recurse -Force $dst -ErrorAction SilentlyContinue
            Move-Item -Force $src $dst
            Log "Installed program folder: $name"
        }
        $automationSrc=Join-Path $stage 'automation.cmd'
        if(Test-Path $automationSrc){Copy-Item -Force $automationSrc (Join-Path $Root 'automation.cmd')}
        $sharedSrc=Join-Path $stage 'data\shared_values.json';$sharedDst=Join-Path $Root 'data\shared_values.json'
        if((Test-Path $sharedSrc) -and (-not(Test-Path $sharedDst))){Copy-Item -Force $sharedSrc $sharedDst}
        $exampleSrc=Join-Path $stage 'modules\example_registration';$exampleDst=Join-Path $Root 'modules\example_registration'
        if((Test-Path $exampleSrc) -and (-not(Test-Path $exampleDst))){Copy-Item -Recurse -Force $exampleSrc $exampleDst}
        Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
        if(-not((Test-Path $ccGui) -and (Test-Path $ccRouter))){throw "Control Center files are incomplete after extraction."}
        $installedCc=$expectedCc
        Action "CONTROL_CENTER" "OK" "Version=$installedCc"
    } else { Action "CONTROL_CENTER" "SKIP" "Program files already present. Version=$installedCc" }

    # Always run compatibility repair, even after SKIP, so an already-installed
    # broken GUI from an earlier package is repaired on the next self-update.
    Repair-ControlCenterGui -GuiPath $ccGui -PythonExe $pythonExe -ExpectedVersion $expectedCc

    Action "LAUNCHERS" "REFRESH" "Refreshing dynamic launchers and installer helpers from GitHub"
    $rootScripts=@('START_CHROME_DEBUG.cmd','START_CONTROL_CENTER.cmd','UPDATE_PLATFORM.cmd')
    $installerScripts=@('INSTALLER_UI.ps1','BOOTSTRAP_RUNNER.ps1','START_PLATFORM_INSTALLER.ps1','PYTHON_RUNTIME_MANAGER.ps1','CHROME_RUNTIME_MANAGER.ps1','PLATFORM_FINALIZER.ps1','INSTALLER_CORE.ps1','START_INSTALLER_GUI.cmd','REPAIR_PYTHON_RUNTIME.ps1','INSTALL_AutomationPlatform.ps1')
    foreach($name in $rootScripts){Download ($rawBase+$name) (Join-Path $Root $name);Log "Deployed root entry: $name"}
    foreach($name in $installerScripts){Download ($rawBase+$name) (Join-Path $installerDir $name);Log "Deployed installer helper: $name"}
    $rootBat=Join-Path $Root 'INSTALL_AutomationPlatform.bat'
    if(-not(Test-Path $rootBat)){Download ($rawBase+'INSTALL_AutomationPlatform.bat') $rootBat;Log "Deployed stable bootstrap BAT"}
    else{Log "Bootstrap BAT preserved; it always fetches the latest INSTALLER_UI.ps1 from GitHub"}

    $debugPort=9222;$cdpHost='127.0.0.1'
    try{$debugPort=[int]$manifest.defaults.debug_port}catch{}
    try{if($manifest.defaults.cdp_host){$cdpHost=[string]$manifest.defaults.cdp_host}}catch{}
    $config=[ordered]@{
        schema_version=3;platform_api=[int]$manifest.platform_api;installed_at=(Get-Date).ToString('o');root=$Root;manifest_url=$ManifestUrl;manifest_schema_version=[int]$manifest.schema_version;finalizer_version=$FinalizerVersion;control_center_version=$expectedCc;python_version=$pythonVersion;python_exe=$pythonExe;chrome_version=$chromeVersion;chrome_exe=$chromeExe;chrome_source='system';chrome_profile=$profile;cdp_host=$cdpHost;debug_port=$debugPort
    }
    $config|ConvertTo-Json -Depth 10|Set-Content -Encoding UTF8 $configPath
    Log "Wrote config: $configPath"

    $status=[ordered]@{
        schema_version=2;generated_at=(Get-Date).ToString('o');overall_status='ok';root=$Root;components=[ordered]@{
            python=[ordered]@{status='ok';action='PREVERIFIED';installed_version=$pythonVersion;tkinter=$tk;pip=$pip;path=$pythonExe};
            chrome=[ordered]@{status='ok';action='PREVERIFIED';installed_version=$chromeVersion;path=$chromeExe};
            control_center=[ordered]@{status='ok';action=$ccAction;installed_version=$installedCc;expected_version=$expectedCc;healthy=$true;fxbutton_patch='ok'};
            chrome_profile=[ordered]@{status='ok';exists=(Test-Path $profile);path=$profile};
            launchers=[ordered]@{status='ok';action='REFRESH'}
        }
    }
    $statusPath=Join-Path $dataDir 'platform_status.json';$status|ConvertTo-Json -Depth 10|Set-Content -Encoding UTF8 $statusPath
    Log "Status file: $statusPath"

    Action "HEALTH" "OK" "Python=$pythonVersion Chrome=$chromeVersion ControlCenter=$installedCc FXButtonPatch=OK Profile=True"
    Copy-Item -Force $logFile $latestLog
    exit 0
}
catch{
    Log "FATAL: $($_.Exception.Message)" "ERROR"
    try{Log $_.ScriptStackTrace "ERROR"}catch{}
    try{Copy-Item -Force $logFile $latestLog}catch{}
    exit 1
}
