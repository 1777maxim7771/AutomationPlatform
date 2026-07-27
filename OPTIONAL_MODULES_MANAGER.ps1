param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$ManifestUrl,
    [switch]$InstallDynamicConversationExporter
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ManagerVersion = "2026.07.27.2"

$Root = $Root.Trim().Trim([char]0x22,[char]0x27).TrimEnd('\','/').Trim()
if(-not $Root){ throw "Root path is empty." }

$logDir       = Join-Path $Root "logs"
$dataDir      = Join-Path $Root "data"
$downloadsDir = Join-Path $Root "_bootstrap\downloads"
$stageRoot    = Join-Path $Root "_bootstrap\module_stage"
$modulesRoot  = Join-Path $Root "modules"
foreach($d in @($logDir,$dataDir,$downloadsDir,$stageRoot,$modulesRoot)){
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

$stamp         = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile       = Join-Path $logDir "optional_modules_$stamp.log"
$latestLog     = Join-Path $logDir "latest_optional_modules.log"
$statusPath    = Join-Path $dataDir "optional_modules_status.json"
$depsStatePath = Join-Path $dataDir "module_dependencies.json"
"=== AutomationPlatform Optional Modules Manager $ManagerVersion ===" | Set-Content -Encoding UTF8 $logFile

function Log([string]$Text,[string]$Level="INFO"){
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$Level,$Text
    Write-Host $line
    Add-Content -Encoding UTF8 -Path $logFile -Value $line
}
function Action([string]$Id,[string]$Action,[string]$Text){ Log "[MODULE:$Id][$Action] $Text" }
function Get-Json([string]$Url){
    $sep = if($Url -match '\?'){'&'}else{'?'}
    Invoke-RestMethod -Uri "$Url$sep`nocache=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
}
function Download([string]$Url,[string]$Dest){
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dest) | Out-Null
    $sep = if($Url -match '\?'){'&'}else{'?'}
    $fetch = "$Url$sep`nocache=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
    Log "DOWNLOAD $fetch"
    Invoke-WebRequest -UseBasicParsing -Uri $fetch -OutFile $Dest
    if(-not(Test-Path $Dest)){ throw "Download failed: $Url" }
    Log ("DOWNLOADED {0} bytes -> {1}" -f (Get-Item $Dest).Length,$Dest)
}
function Resolve-RawUrl([string]$BaseUrl,[string]$Relative){
    (New-Object System.Uri([Uri]$BaseUrl,([string]$Relative).Replace('\','/'))).AbsoluteUri
}
function Get-InstalledVersion([string]$Target){
    $meta = Join-Path $Target 'module.json'
    if(-not(Test-Path $meta)){ return $null }
    try { [string]((Get-Content -Raw -Encoding UTF8 $meta | ConvertFrom-Json).version) } catch { $null }
}
function Test-RequiredFiles([string]$Base,$Required){
    foreach($rel in @($Required)){
        if(-not(Test-Path (Join-Path $Base ([string]$rel)))){ return $false }
    }
    $true
}
function Read-JsonFile([string]$Path){
    if(Test-Path $Path){ try { Get-Content -Raw -Encoding UTF8 $Path | ConvertFrom-Json } catch { $null } }
}
function Test-ModuleImports([string]$PythonExe){
    if(-not(Test-Path $PythonExe)){ return $false }
    try {
        & $PythonExe -c "import playwright, markdownify; import pyvda" 2>$null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}
function Ensure-Requirements([string]$Id,[string]$PythonExe,[string]$RequirementsPath){
    if(-not(Test-Path $RequirementsPath)){
        Action $Id 'DEPENDENCIES_SKIP' 'requirements.txt is not present.'
        return
    }
    if(-not(Test-Path $PythonExe)){ throw "Platform-local Python is missing: $PythonExe" }

    $hash = (Get-FileHash -Algorithm SHA256 -Path $RequirementsPath).Hash.ToLowerInvariant()
    $state = Read-JsonFile $depsStatePath
    $oldHash = $null
    try { $oldHash = [string]$state.$Id.requirements_sha256 } catch {}

    if((Test-ModuleImports $PythonExe) -and $oldHash -eq $hash){
        Action $Id 'DEPENDENCIES_SKIP' "Already healthy. requirements_sha256=$hash"
        return
    }

    Action $Id 'DEPENDENCIES_INSTALL' "Installing requirements with platform-local Python. hash=$hash"
    & $PythonExe -m pip install -r $RequirementsPath 2>&1 | ForEach-Object { Log ("[pip] " + [string]$_) }
    if($LASTEXITCODE -ne 0){ throw "Python requirements installation failed for module $Id." }
    if(-not(Test-ModuleImports $PythonExe)){ throw "Module Python dependency verification failed after pip install." }

    $all = [ordered]@{}
    if($state){ foreach($p in $state.PSObject.Properties){ $all[$p.Name] = $p.Value } }
    $all[$Id] = [ordered]@{ requirements_sha256=$hash; verified_at=(Get-Date).ToString('o') }
    $all | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $depsStatePath
    Action $Id 'DEPENDENCIES_OK' 'Python requirements verified.'
}
function Copy-Preserved([string]$Target,[string]$Backup,$Items){
    Remove-Item -Recurse -Force $Backup -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $Backup | Out-Null
    foreach($rel in @($Items)){
        $src = Join-Path $Target ([string]$rel)
        if(Test-Path $src){
            $dst = Join-Path $Backup ([string]$rel)
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
            if((Get-Item $src).PSIsContainer){ Copy-Item -Recurse -Force $src $dst } else { Copy-Item -Force $src $dst }
            Log "PRESERVE $rel"
        }
    }
}
function Restore-Preserved([string]$Backup,[string]$Target,$Items){
    foreach($rel in @($Items)){
        $src = Join-Path $Backup ([string]$rel)
        if(Test-Path $src){
            $dst = Join-Path $Target ([string]$rel)
            Remove-Item -Recurse -Force $dst -ErrorAction SilentlyContinue
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
            if((Get-Item $src).PSIsContainer){ Copy-Item -Recurse -Force $src $dst } else { Copy-Item -Force $src $dst }
            Log "RESTORE $rel"
        }
    }
}
function Write-RootLauncher([string]$Target){
    $launcher = Join-Path $Root 'START_DYNAMIC_CONVERSATION_EXPORTER.cmd'
    $entry = Join-Path $Target '00_START_ALL.cmd'
    $lines = @(
        '@echo off',
        'setlocal EnableExtensions',
        ('cd /d "{0}"' -f $Root),
        ('if not exist "{0}" (' -f $entry),
        '  echo [ERROR] Dynamic Conversation Exporter is not installed.',
        '  pause',
        '  exit /b 1',
        ')',
        ('call "{0}"' -f $entry),
        'exit /b %ERRORLEVEL%'
    )
    $lines | Set-Content -Encoding ASCII $launcher
    $launcher
}
function Get-ModulePackage($Remote,[string]$Id){
    $version = [string]$Remote.version
    $package = Join-Path $downloadsDir ("{0}-{1}.zip" -f $Id,$version)
    $expected = ([string]$Remote.package_sha256).ToLowerInvariant()

    if((Test-Path $package) -and $expected){
        $cached = (Get-FileHash -Algorithm SHA256 -Path $package).Hash.ToLowerInvariant()
        if($cached -eq $expected){
            Action $Id 'PACKAGE_CACHE' "Valid cached package reused: $package"
            return $package
        }
    }

    $parts = @($Remote.package_parts)
    if($parts.Count -lt 1){ throw "Module manifest has no package_parts." }
    $builder = New-Object System.Text.StringBuilder
    $i = 0
    foreach($part in $parts){
        $i++
        $url = Resolve-RawUrl ([string]$Remote.repository + '/blob/main/module_manifest.json') ([string]$part)
        # Resolve against the real manifest URL when possible. GitHub blob URL above is only a fallback base.
        if($Remote.PSObject.Properties.Name -contains '_manifest_url'){
            $url = Resolve-RawUrl ([string]$Remote._manifest_url) ([string]$part)
        }
        $partFile = Join-Path $downloadsDir ("{0}-{1}-part{2:D2}.b64" -f $Id,$version,$i)
        Action $Id 'DOWNLOAD' "Package part $i/$($parts.Count)"
        Download $url $partFile
        [void]$builder.Append(((Get-Content -Raw -Encoding UTF8 $partFile) -replace '\s',''))
    }

    try { [IO.File]::WriteAllBytes($package,[Convert]::FromBase64String($builder.ToString())) }
    catch { throw "Could not decode module package: $($_.Exception.Message)" }

    $actual = (Get-FileHash -Algorithm SHA256 -Path $package).Hash.ToLowerInvariant()
    if($expected -and $actual -ne $expected){
        Remove-Item -Force $package -ErrorAction SilentlyContinue
        throw "Module package SHA-256 mismatch. Expected=$expected Actual=$actual"
    }
    Action $Id 'PACKAGE_OK' "SHA-256=$actual"
    $package
}
function Install-DynamicConversationExporter($Definition,[bool]$ExplicitInstall){
    $id = [string]$Definition.id
    $target = Join-Path $Root ([string]$Definition.install_directory)
    $installed = Test-Path (Join-Path $target 'module.json')
    $installedVersion = Get-InstalledVersion $target

    if((-not $installed) -and (-not $ExplicitInstall)){
        Action $id 'SKIP_OPTIONAL' 'Not installed and not selected in the installer.'
        return [ordered]@{id=$id;status='not_installed';action='SKIP_OPTIONAL';installed=$false;version=$null;path=$target}
    }

    $manifestUrl = [string]$Definition.manifest_url
    $remote = Get-Json $manifestUrl
    # Add a local helper property used only by this manager to resolve package_parts.
    $remote | Add-Member -NotePropertyName '_manifest_url' -NotePropertyValue $manifestUrl -Force
    $expectedVersion = [string]$remote.version
    $required = @($remote.required_files)
    $healthy = $installed -and (Test-RequiredFiles $target $required)
    $need = (-not $installed) -or (-not $healthy) -or ($installedVersion -ne $expectedVersion)

    if(-not $need){
        Action $id 'SKIP' "Already current and healthy. Version=$installedVersion"
        Ensure-Requirements $id (Join-Path $Root 'runtime\python\python.exe') (Join-Path $target ([string]$remote.requirements))
        $launcher = Write-RootLauncher $target
        return [ordered]@{id=$id;status='ok';action='SKIP';installed=$true;version=$installedVersion;expected_version=$expectedVersion;path=$target;launcher=$launcher}
    }

    $action = if(-not $installed){'INSTALL'}elseif(-not $healthy){'REPAIR'}else{'UPDATE'}
    Action $id $action "Installed=$installedVersion Expected=$expectedVersion Healthy=$healthy"
    $package = Get-ModulePackage $remote $id

    $stage = Join-Path $stageRoot ($id + '_new')
    $backup = Join-Path $stageRoot ($id + '_preserved')
    $rollback = Join-Path $stageRoot ($id + '_rollback')
    Remove-Item -Recurse -Force $stage,$rollback -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Expand-Archive -Path $package -DestinationPath $stage -Force
    if(-not(Test-RequiredFiles $stage $required)){ throw "Staged module is incomplete; required files are missing." }

    if($installed){ Copy-Preserved $target $backup @($remote.preserve_on_update) }
    if(Test-Path $target){ Move-Item -Force $target $rollback }

    try {
        Move-Item -Force $stage $target
        if(Test-Path $backup){ Restore-Preserved $backup $target @($remote.preserve_on_update) }
        if(-not(Test-RequiredFiles $target $required)){ throw "Installed module verification failed." }
        $finalVersion = Get-InstalledVersion $target
        if($finalVersion -ne $expectedVersion){ throw "Installed module version mismatch. Expected=$expectedVersion Actual=$finalVersion" }
        Ensure-Requirements $id (Join-Path $Root 'runtime\python\python.exe') (Join-Path $target ([string]$remote.requirements))
        $launcher = Write-RootLauncher $target
        Remove-Item -Recurse -Force $rollback,$backup -ErrorAction SilentlyContinue
    } catch {
        Remove-Item -Recurse -Force $target -ErrorAction SilentlyContinue
        if(Test-Path $rollback){ Move-Item -Force $rollback $target }
        throw
    }

    Action $id 'OK' "Version=$expectedVersion Path=$target Launcher=$launcher"
    [ordered]@{id=$id;status='ok';action=$action;installed=$true;version=$expectedVersion;expected_version=$expectedVersion;path=$target;launcher=$launcher}
}

try {
    Log "Root=$Root"
    Log "Manifest=$ManifestUrl"
    Log "InstallDynamicConversationExporter=$([bool]$InstallDynamicConversationExporter)"

    $platform = Get-Json $ManifestUrl
    $results = @()
    if($platform.optional_modules -and $platform.optional_modules.dynamic_conversation_exporter){
        $results += Install-DynamicConversationExporter $platform.optional_modules.dynamic_conversation_exporter ([bool]$InstallDynamicConversationExporter)
    } else {
        Log "No dynamic_conversation_exporter definition exists in platform manifest." "WARN"
    }

    $summary = [ordered]@{schema_version=1;generated_at=(Get-Date).ToString('o');manager_version=$ManagerVersion;modules=$results}
    $summary | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $statusPath
    Log "Status file: $statusPath"
    Copy-Item -Force $logFile $latestLog
    exit 0
} catch {
    Log "FATAL: $($_.Exception.Message)" "ERROR"
    try { Log $_.ScriptStackTrace "ERROR" } catch {}
    try { Copy-Item -Force $logFile $latestLog } catch {}
    exit 1
}
