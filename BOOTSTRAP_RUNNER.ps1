param(
    [string]$Root = "D:\AutomationPlatform",
    [string]$ManifestUrl = "https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/platform_manifest.json",
    [switch]$InstallDynamicConversationExporter,
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root = $Root.Trim().Trim([char]0x22,[char]0x27).TrimEnd('\','/').Trim()
if(-not $Root){throw "Root path is empty."}

$RepoRaw="https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main"
$logDir=Join-Path $Root "logs"
$installerDir=Join-Path $Root "installer"
$tempDir=Join-Path $env:TEMP "AutomationPlatform_Bootstrap"
New-Item -ItemType Directory -Force -Path $Root,$logDir,$installerDir,$tempDir|Out-Null

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$logFile=Join-Path $logDir "bootstrap_$stamp.log"
$latestLog=Join-Path $logDir "latest_bootstrap.log"
$header="=== AutomationPlatform bootstrap $stamp ==="
$header|Set-Content -Encoding UTF8 $logFile
$header|Set-Content -Encoding UTF8 $latestLog

function Log([string]$Text,[string]$Level="INFO"){
    $line="[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$Level,$Text
    Write-Host $line
    Add-Content -Encoding UTF8 -Path $logFile -Value $line
    Add-Content -Encoding UTF8 -Path $latestLog -Value $line
}
function Download([string]$Url,[string]$Dest){
    $sep=if($Url -match '\?'){'&'}else{'?'}
    $fetchUrl="$Url$sep`nocache=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
    Log "DOWNLOAD $fetchUrl"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dest)|Out-Null
    Invoke-WebRequest -UseBasicParsing -Uri $fetchUrl -OutFile $Dest
    if(-not(Test-Path $Dest)){throw "Download failed: $Url"}
    Log ("DOWNLOADED {0} bytes -> {1}" -f (Get-Item $Dest).Length,$Dest)
}
function Run-LoggedPowerShell([string]$Prefix,[string[]]$Arguments){
    & powershell.exe @Arguments 2>&1|ForEach-Object{
        $text=[string]$_
        Write-Host $text
        $line="[$Prefix] $text"
        Add-Content -Encoding UTF8 -Path $logFile -Value $line
        Add-Content -Encoding UTF8 -Path $latestLog -Value $line
    }
    return $LASTEXITCODE
}
function Prepare-ControlCenterPackage($Manifest){
    $encoding="binary";try{if($Manifest.control_center.encoding){$encoding=[string]$Manifest.control_center.encoding}}catch{}
    if($encoding -ne "base64-parts"){return}
    $parts=@($Manifest.control_center.package_parts)
    if($parts.Count -lt 1){throw "Control Center package_parts is empty."}
    $version=[string]$Manifest.control_center.version
    $downloadsDir=Join-Path $Root "_bootstrap\downloads"
    New-Item -ItemType Directory -Force -Path $downloadsDir|Out-Null
    $zipPath=Join-Path $downloadsDir "ControlCenter-$version.zip"
    $expected=([string]$Manifest.control_center.sha256).ToLowerInvariant()

    if((Test-Path $zipPath)-and $expected){
        $cached=(Get-FileHash -Algorithm SHA256 -Path $zipPath).Hash.ToLowerInvariant()
        if($cached -eq $expected){Log "CONTROL_CENTER PACKAGE cache valid; download skipped: $zipPath";return}
    }

    if($expected){
        foreach($candidate in (Get-ChildItem -Path $downloadsDir -Filter 'ControlCenter-*.zip' -File -ErrorAction SilentlyContinue)){
            if($candidate.FullName -eq $zipPath){continue}
            try{
                $candidateSha=(Get-FileHash -Algorithm SHA256 -Path $candidate.FullName).Hash.ToLowerInvariant()
                if($candidateSha -eq $expected){
                    Copy-Item -Force $candidate.FullName $zipPath
                    Log "CONTROL_CENTER PACKAGE reused matching cache: $($candidate.Name) -> $(Split-Path $zipPath -Leaf)"
                    return
                }
            }catch{}
        }
    }

    $builder=New-Object System.Text.StringBuilder
    $index=0
    foreach($part in $parts){
        $index++
        $partUrl=(New-Object System.Uri([Uri]$ManifestUrl,([string]$part).Replace('\','/'))).AbsoluteUri
        $partFile=Join-Path $tempDir ("control_center_{0:D2}.b64" -f $index)
        Log "CONTROL_CENTER PACKAGE part $index/$($parts.Count)"
        Download $partUrl $partFile
        [void]$builder.Append(((Get-Content -Raw -Encoding UTF8 $partFile)-replace '\s',''))
    }
    [IO.File]::WriteAllBytes($zipPath,[Convert]::FromBase64String($builder.ToString()))
    $actual=(Get-FileHash -Algorithm SHA256 -Path $zipPath).Hash.ToLowerInvariant()
    if($expected -and $actual -ne $expected){Remove-Item -Force $zipPath -ErrorAction SilentlyContinue;throw "Control Center reconstructed ZIP SHA-256 mismatch. Expected=$expected Actual=$actual"}
    Log "CONTROL_CENTER PACKAGE ready: $zipPath / SHA-256=$actual"
}

Log "Root=$Root"
Log "Manifest=$ManifestUrl"
Log "Mode=INSTALL_OR_UPDATE_OR_REPAIR"
Log "Optional DynamicConversationExporter selected=$([bool]$InstallDynamicConversationExporter)"

try{
    $manifestFile=Join-Path $tempDir "platform_manifest.json"
    $pythonManagerFile=Join-Path $tempDir "PYTHON_RUNTIME_MANAGER.ps1"
    $chromeManagerFile=Join-Path $tempDir "CHROME_RUNTIME_MANAGER.ps1"
    $finalizerFile=Join-Path $tempDir "PLATFORM_FINALIZER.ps1"
    $optionalManagerFile=Join-Path $tempDir "OPTIONAL_MODULES_MANAGER.ps1"

    Log "Fetching latest manifest and component managers from GitHub"
    Download $ManifestUrl $manifestFile
    $manifest=Get-Content -Raw -Encoding UTF8 $manifestFile|ConvertFrom-Json
    Log "Manifest schema=$($manifest.schema_version), ControlCenter=$($manifest.control_center.version), Python=$($manifest.python.version), PythonMethod=$($manifest.python.method)"

    Download "$RepoRaw/PYTHON_RUNTIME_MANAGER.ps1" $pythonManagerFile
    Download "$RepoRaw/CHROME_RUNTIME_MANAGER.ps1" $chromeManagerFile
    Download "$RepoRaw/PLATFORM_FINALIZER.ps1" $finalizerFile
    Download "$RepoRaw/OPTIONAL_MODULES_MANAGER.ps1" $optionalManagerFile
    Copy-Item -Force $pythonManagerFile (Join-Path $installerDir "PYTHON_RUNTIME_MANAGER.ps1")
    Copy-Item -Force $chromeManagerFile (Join-Path $installerDir "CHROME_RUNTIME_MANAGER.ps1")
    Copy-Item -Force $finalizerFile (Join-Path $installerDir "PLATFORM_FINALIZER.ps1")
    Copy-Item -Force $optionalManagerFile (Join-Path $installerDir "OPTIONAL_MODULES_MANAGER.ps1")
    Copy-Item -Force $manifestFile (Join-Path $installerDir "platform_manifest.json")

    Log "PHASE 1/5 - Python runtime health"
    $pyArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$pythonManagerFile,'-Root',$Root,'-ManifestUrl',$ManifestUrl)
    $pyExit=Run-LoggedPowerShell "PYTHON-RUNTIME" $pyArgs
    if($pyExit -ne 0){throw "Python Runtime Manager failed with exit code $pyExit"}

    Log "PHASE 2/5 - Chrome runtime health"
    $chromeArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$chromeManagerFile,'-Root',$Root,'-ManifestUrl',$ManifestUrl)
    $chromeExit=Run-LoggedPowerShell "CHROME-RUNTIME" $chromeArgs
    if($chromeExit -ne 0){throw "Chrome Runtime Manager failed with exit code $chromeExit"}

    Log "PHASE 3/5 - Control Center package"
    Prepare-ControlCenterPackage $manifest

    Log "PHASE 4/5 - Platform finalizer"
    $finArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$finalizerFile,'-Root',$Root,'-ManifestUrl',$ManifestUrl)
    $finExit=Run-LoggedPowerShell "FINALIZER" $finArgs
    if($finExit -ne 0){throw "Platform Finalizer failed with exit code $finExit"}

    Log "PHASE 5/5 - Optional modules"
    $moduleArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$optionalManagerFile,'-Root',$Root,'-ManifestUrl',$ManifestUrl)
    if($InstallDynamicConversationExporter){$moduleArgs += '-InstallDynamicConversationExporter'}
    $moduleExit=Run-LoggedPowerShell "OPTIONAL-MODULES" $moduleArgs
    if($moduleExit -ne 0){throw "Optional Modules Manager failed with exit code $moduleExit"}

    $statusPath=Join-Path $Root "data\platform_status.json"
    if(Test-Path $statusPath){
        try{
            $status=Get-Content -Raw -Encoding UTF8 $statusPath|ConvertFrom-Json
            Log "Health overall=$($status.overall_status)"
            Log "Python status=$($status.components.python.status), action=$($status.components.python.action), version=$($status.components.python.installed_version)"
            Log "Chrome status=$($status.components.chrome.status), action=$($status.components.chrome.action), version=$($status.components.chrome.installed_version)"
            Log "ControlCenter status=$($status.components.control_center.status), action=$($status.components.control_center.action), version=$($status.components.control_center.installed_version)"
        }catch{Log "Could not parse platform_status.json: $($_.Exception.Message)" "WARN"}
    }
    $optionalStatus=Join-Path $Root "data\optional_modules_status.json"
    if(Test-Path $optionalStatus){
        try{
            $mods=Get-Content -Raw -Encoding UTF8 $optionalStatus|ConvertFrom-Json
            foreach($m in @($mods.modules)){Log "OptionalModule id=$($m.id), status=$($m.status), action=$($m.action), version=$($m.version)"}
        }catch{Log "Could not parse optional_modules_status.json: $($_.Exception.Message)" "WARN"}
    }

    Log "Bootstrap completed successfully"
    if(-not $NoLaunch){
        $launcher=Join-Path $Root "START_CONTROL_CENTER.cmd"
        if(Test-Path $launcher){Log "Launching Control Center: $launcher";Start-Process -FilePath $launcher -WorkingDirectory $Root}
        else{Log "Control Center launcher missing after successful install: $launcher" "WARN"}
    }
    exit 0
}
catch{
    Log "FATAL: $($_.Exception.Message)" "ERROR"
    try{Log $_.ScriptStackTrace "ERROR"}catch{}
    Write-Host ""
    Write-Host "[ERROR] AutomationPlatform setup/update failed." -ForegroundColor Red
    Write-Host "Log: $logFile" -ForegroundColor Yellow
    exit 1
}
