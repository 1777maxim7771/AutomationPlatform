param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$ManifestUrl,
    [switch]$InstallDynamicConversationExporter
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ManagerVersion = "2026.07.27.1"

$Root = $Root.Trim().Trim([char]0x22,[char]0x27).TrimEnd('\','/').Trim()
if(-not $Root){throw "Root path is empty."}

$logDir = Join-Path $Root "logs"
$dataDir = Join-Path $Root "data"
$downloadsDir = Join-Path $Root "_bootstrap\downloads"
$stageRoot = Join-Path $Root "_bootstrap\module_stage"
$modulesRoot = Join-Path $Root "modules"
foreach($d in @($logDir,$dataDir,$downloadsDir,$stageRoot,$modulesRoot)){New-Item -ItemType Directory -Force -Path $d | Out-Null}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $logDir "optional_modules_$stamp.log"
$latestLog = Join-Path $logDir "latest_optional_modules.log"
$statusPath = Join-Path $dataDir "optional_modules_status.json"
$depsStatePath = Join-Path $dataDir "module_dependencies.json"
"=== AutomationPlatform Optional Modules Manager $ManagerVersion ===" | Set-Content -Encoding UTF8 $logFile

function Log([string]$Text,[string]$Level="INFO"){
    $line="[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$Level,$Text
    Write-Host $line
    Add-Content -Encoding UTF8 -Path $logFile -Value $line
}
function Action([string]$Id,[string]$Action,[string]$Text){Log "[MODULE:$Id][$Action] $Text"}
function Download([string]$Url,[string]$Dest){
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dest)|Out-Null
    $sep=if($Url -match '\?'){'&'}else{'?'}
    $fetch="$Url$sep`nocache=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
    Log "DOWNLOAD $fetch"
    Invoke-WebRequest -UseBasicParsing -Uri $fetch -OutFile $Dest
    if(-not(Test-Path $Dest)){throw "Download failed: $Url"}
    Log ("DOWNLOADED {0} bytes -> {1}" -f (Get-Item $Dest).Length,$Dest)
}
function Get-Json([string]$Url){
    $sep=if($Url -match '\?'){'&'}else{'?'}
    return Invoke-RestMethod -Uri "$Url$sep`nocache=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
}
function Resolve-RawUrl([string]$BaseUrl,[string]$Relative){
    return (New-Object System.Uri([Uri]$BaseUrl,([string]$Relative).Replace('\','/'))).AbsoluteUri
}
function Version-Lt([string]$Current,[string]$Expected){
    try{return ([version]$Current -lt [version]$Expected)}catch{return ($Current -ne $Expected)}
}
function Get-InstalledVersion([string]$Target){
    $p=Join-Path $Target 'module.json'
    if(-not(Test-Path $p)){return $null}
    try{return [string]((Get-Content -Raw -Encoding UTF8 $p|ConvertFrom-Json).version)}catch{return $null}
}
function Test-RequiredFiles([string]$RootDir,$Required){
    foreach($rel in @($Required)){if(-not(Test-Path (Join-Path $RootDir ([string]$rel)))){return $false}}
    return $true
}
function Read-State([string]$Path){if(Test-Path $Path){try{return Get-Content -Raw -Encoding UTF8 $Path|ConvertFrom-Json}catch{}};return $null}
function Requirements-Healthy([string]$PythonExe){
    if(-not(Test-Path $PythonExe)){return $false}
    try{& $PythonExe -c "import playwright, markdownify; import pyvda" 2>$null;return($LASTEXITCODE -eq 0)}catch{return $false}
}
function Ensure-Requirements([string]$ModuleId,[string]$PythonExe,[string]$RequirementsPath){
    if(-not(Test-Path $RequirementsPath)){Action $ModuleId 'DEPENDENCIES_SKIP' 'requirements.txt is not present.';return}
    if(-not(Test-Path $PythonExe)){throw "Platform-local Python is missing: $PythonExe"}
    $hash=(Get-FileHash -Algorithm SHA256 -Path $RequirementsPath).Hash.ToLowerInvariant()
    $state=Read-State $depsStatePath
    $old=$null
    try{$old=[string]$state.$ModuleId.requirements_sha256}catch{}
    $healthy=Requirements-Healthy $PythonExe
    if($healthy -and $old -eq $hash){Action $ModuleId 'DEPENDENCIES_SKIP' "Already healthy. requirements_sha256=$hash";return}
    Action $ModuleId 'DEPENDENCIES_INSTALL' "Installing/updating requirements with platform-local Python. hash=$hash"
    & $PythonExe -m pip install -r $RequirementsPath 2>&1 | ForEach-Object {Log ("[pip] "+[string]$_)}
    if($LASTEXITCODE -ne 0){throw "Python requirements installation failed for module $ModuleId."}
    if(-not(Requirements-Healthy $PythonExe)){throw "Module Python dependency verification failed after pip install."}
    $all=[ordered]@{}
    if($state){foreach($prop in $state.PSObject.Properties){$all[$prop.Name]=$prop.Value}}
    $all[$ModuleId]=[ordered]@{requirements_sha256=$hash;verified_at=(Get-Date).ToString('o')}
    $all|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 $depsStatePath
    Action $ModuleId 'DEPENDENCIES_OK' 'Python requirements verified.'
}
function Backup-Preserved([string]$Target,[string]$BackupRoot,$Items){
    New-Item -ItemType Directory -Force -Path $BackupRoot|Out-Null
    foreach($rel in @($Items)){
        $src=Join-Path $Target ([string]$rel)
        if(Test-Path $src){
            $dst=Join-Path $BackupRoot ([string]$rel)
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst)|Out-Null
            if((Get-Item $src).PSIsContainer){Copy-Item -Recurse -Force $src $dst}else{Copy-Item -Force $src $dst}
            Log "PRESERVE $rel"
        }
    }
}
function Restore-Preserved([string]$BackupRoot,[string]$Target,$Items){
    foreach($rel in @($Items)){
        $src=Join-Path $BackupRoot ([string]$rel)
        if(Test-Path $src){
            $dst=Join-Path $Target ([string]$rel)
            Remove-Item -Recurse -Force $dst -ErrorAction SilentlyContinue
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst)|Out-Null
            if((Get-Item $src).PSIsContainer){Copy-Item -Recurse -Force $src $dst}else{Copy-Item -Force $src $dst}
            Log "RESTORE $rel"
        }
    }
}
function Install-PackageModule($Definition,[bool]$ExplicitInstall){
    $id=[string]$Definition.id
    $moduleManifestUrl=[string]$Definition.manifest_url
    $target=Join-Path $Root ([string]$Definition.install_directory)
    $installed=Test-Path (Join-Path $target 'module.json')
    $installedVersion=Get-InstalledVersion $target

    if((-not $installed) -and (-not $ExplicitInstall)){
        Action $id 'SKIP_OPTIONAL' 'Not installed and not selected in the installer.'
        return [ordered]@{id=$id;status='not_installed';action='SKIP_OPTIONAL';installed=$false;version=$null;path=$target}
    }

    $remote=Get-Json $moduleManifestUrl
    $expectedVersion=[string]$remote.version
    $required=@($remote.required_files)
    $healthy=$installed -and (Test-RequiredFiles $target $required)
    $needInstall=(-not $installed) -or (-not $healthy) -or (Version-Lt $installedVersion $expectedVersion)

    if(-not $needInstall){
        Action $id 'SKIP' "Already current and healthy. Version=$installedVersion"
        Ensure-Requirements $id (Join-Path $Root 'runtime\python\python.exe') (Join-Path $target ([string]$remote.requirements))
        return [ordered]@{id=$id;status='ok';action='SKIP';installed=$true;version=$installedVersion;expected_version=$expectedVersion;path=$target}
    }

    $action=if(-not $installed){'INSTALL'}elseif(-not $healthy){'REPAIR'}else{'UPDATE'}
    Action $id $action "Installed=$installedVersion Expected=$expectedVersion Healthy=$healthy"

    $packageParts=@($remote.package_parts)
    if($packageParts.Count -lt 1){throw "Module manifest has no package_parts: $moduleManifestUrl"}
    $packageFile=Join-Path $downloadsDir ("{0}-{1}.zip" -f $id,$expectedVersion)
    $expectedSha=([string]$remote.package_sha256).ToLowerInvariant()
    $cacheOk=$false
    if((Test-Path $packageFile)-and $expectedSha){
        $cacheSha=(Get-FileHash -Algorithm SHA256 -Path $packageFile).Hash.ToLowerInvariant()
        $cacheOk=($cacheSha -eq $expectedSha)
    }
    if($cacheOk){Action $id 'PACKAGE_CACHE' "Valid cached package reused: $packageFile"}
    else{
        $builder=New-Object System.Text.StringBuilder
        $i=0
        foreach($part in $packageParts){
            $i++
            $partUrl=Resolve-RawUrl $moduleManifestUrl ([string]$part)
            $partFile=Join-Path $downloadsDir ("{0}-{1}-part{2:D2}.b64" -f $id,$expectedVersion,$i)
            Action $id 'DOWNLOAD' "Package part $i/$($packageParts.Count)"
            Download $partUrl $partFile
            [void]$builder.Append(((Get-Content -Raw -Encoding UTF8 $partFile)-replace '\s',''))
        }
        try{[IO.File]::WriteAllBytes($packageFile,[Convert]::FromBase64String($builder.ToString()))}catch{throw "Could not decode module package: $($_.Exception.Message)"}
        $actual=(Get-FileHash -Algorithm SHA256 -Path $packageFile).Hash.ToLowerInvariant()
        if($expectedSha -and $actual -ne $expectedSha){Remove-Item -Force $packageFile -ErrorAction SilentlyContinue;throw "Module package SHA-256 mismatch. Expected=$expectedSha Actual=$actual"}
        Action $id 'PACKAGE_OK' "SHA-256=$actual"
    }

    $stage=Join-Path $stageRoot $id
    $backup=Join-Path $stageRoot ($id+'_preserved')
    Remove-Item -Recurse -Force $stage,$backup -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $stage|Out-Null
    Expand-Archive -Path $packageFile -DestinationPath $stage -Force
    if(-not(Test-RequiredFiles $stage $required)){throw "Staged module is incomplete; required files are missing."}

    if($installed){Backup-Preserved $target $backup @($remote.preserve_on_update)}
    $rollback=Join-Path $stageRoot ($id+'_rollback')
    Remove-Item -Recurse -Force $rollback -ErrorAction SilentlyContinue
    if(Test-Path $target){Move-Item -Force $target $rollback}
    try{
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target)|Out-Null
        Move-Item -Force $stage $target
        if(Test-Path $backup){Restore-Preserved $backup $target @($remote.preserve_on_update)}
        if(-not(Test-RequiredFiles $target $required)){throw "Installed module verification failed."}
        $finalVersion=Get-InstalledVersion $target
        if($finalVersion -ne $expectedVersion){throw "Installed module version mismatch. Expected=$expectedVersion Actual=$finalVersion"}
        Ensure-Requirements $id (Join-Path $Root 'runtime\python\python.exe') (Join-Path $target ([string]$remote.requirements))
        Remove-Item -Recurse -Force $rollback,$backup -ErrorAction SilentlyContinue
    }catch{
        Remove-Item -Recurse -Force $target -ErrorAction SilentlyContinue
        if(Test-Path $rollback){Move-Item -Force $rollback $target}
        throw
    }

    $launcher=Join-Path $Root 'START_DYNAMIC_CONVERSATION_EXPORTER.cmd'
    @"
@echo off
setlocal EnableExtensions
cd /d "%Root%"
if not exist "%Root%\modules\dynamic_conversation_exporter\00_START_ALL.cmd" (
  echo [ERROR] Dynamic Conversation Exporter is not installed.
  pause
  exit /b 1
)
call "%Root%\modules\dynamic_conversation_exporter\00_START_ALL.cmd"
exit /b %%ERRORLEVEL%%
"@.Replace('%Root%',$Root)|Set-Content -Encoding ASCII $launcher
    Action $id 'OK' "Version=$expectedVersion Path=$target Launcher=$launcher"
    return [ordered]@{id=$id;status='ok';action=$action;installed=$true;version=$expectedVersion;expected_version=$expectedVersion;path=$target;launcher=$launcher}
}

try{
    Log "Root=$Root"
    Log "Manifest=$ManifestUrl"
    Log "InstallDynamicConversationExporter=$([bool]$InstallDynamicConversationExporter)"
    $platform=Get-Json $ManifestUrl
    $results=@()
    if($platform.optional_modules -and $platform.optional_modules.dynamic_conversation_exporter){
        $results += Install-PackageModule $platform.optional_modules.dynamic_conversation_exporter ([bool]$InstallDynamicConversationExporter)
    }else{
        Log "No dynamic_conversation_exporter definition exists in platform manifest." "WARN"
    }
    $summary=[ordered]@{schema_version=1;generated_at=(Get-Date).ToString('o');manager_version=$ManagerVersion;modules=$results}
    $summary|ConvertTo-Json -Depth 10|Set-Content -Encoding UTF8 $statusPath
    Log "Status file: $statusPath"
    Copy-Item -Force $logFile $latestLog
    exit 0
}catch{
    Log "FATAL: $($_.Exception.Message)" "ERROR"
    try{Log $_.ScriptStackTrace "ERROR"}catch{}
    try{Copy-Item -Force $logFile $latestLog}catch{}
    exit 1
}
