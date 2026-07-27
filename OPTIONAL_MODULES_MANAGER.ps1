param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$ManifestUrl,
    [switch]$InstallDynamicConversationExporter
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ManagerVersion = "2026.07.27.4"

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
function Add-CacheBuster([string]$Url){
    $sep = if($Url -match '\?'){'&'}else{'?'}
    return ("{0}{1}nocache={2}" -f $Url,$sep,[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
}
function Get-Json([string]$Url){
    $fetch = Add-CacheBuster $Url
    Log "GET JSON $fetch"
    Invoke-RestMethod -Uri $fetch
}
function Download([string]$Url,[string]$Dest){
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dest) | Out-Null
    $fetch = Add-CacheBuster $Url
    Log "DOWNLOAD $fetch"
    Invoke-WebRequest -UseBasicParsing -Uri $fetch -OutFile $Dest
    if(-not(Test-Path $Dest)){ throw "Download failed: $Url" }
    $size = (Get-Item $Dest).Length
    if($size -le 0){ throw "Downloaded file is empty: $Url" }
    Log ("DOWNLOADED {0} bytes -> {1}" -f $size,$Dest)
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
        ('set "AUTOMATION_PLATFORM_ROOT={0}"' -f $Root),
        ('set "AUTOMATION_PLATFORM_PYTHON={0}"' -f (Join-Path $Root 'runtime\python\python.exe')),
        ('set "AUTOMATION_PLATFORM_PROFILE={0}"' -f (Join-Path $Root 'browser\Chrome_Profile')),
        'set "AUTOMATION_PLATFORM_CDP_URL=http://127.0.0.1:9222"',
        'set "AUTOMATION_PLATFORM_CDP_PORT=9222"',
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
function Sync-EmbeddedIntegration($Remote,[string]$Target,[string]$Id){
    if(-not $Remote.ui){
        Action $Id 'UI_SKIP' 'Remote manifest has no ui contract.'
        return $null
    }
    if(([string]$Remote.ui.mode) -ne 'embedded'){
        Action $Id 'UI_SKIP' "UI mode=$($Remote.ui.mode)"
        return $null
    }
    $uiApi = [int]$Remote.ui.ui_api
    if($uiApi -gt 1){ throw "Module $Id requires unsupported embedded UI API $uiApi." }
    $source = [string]$Remote.ui.source
    $installedFile = [string]$Remote.ui.installed_file
    if(-not $installedFile){ $installedFile = $source }
    if(-not $source){ throw "Embedded UI source is missing in module manifest." }
    $manifestUrl = [string]$Remote._manifest_url
    $sourceUrl = Resolve-RawUrl $manifestUrl $source
    $dest = Join-Path $Target $installedFile
    Action $Id 'UI_SYNC' "$source -> $dest"
    Download $sourceUrl $dest

    $python = Join-Path $Root 'runtime\python\python.exe'
    & $python -m py_compile $dest 2>&1 | ForEach-Object { Log ("[ui-py_compile] " + [string]$_) }
    if($LASTEXITCODE -ne 0){ throw "Embedded UI Python syntax validation failed for $Id." }

    $integration = [ordered]@{
        schema_version=1
        module_id=$Id
        name=[string]$Remote.name
        version=[string]$Remote.version
        integration_revision=[int]$Remote.integration_revision
        repository=[string]$Remote.repository
        ui_mode='embedded'
        ui_api=$uiApi
        ui_file=$installedFile
        entry_class=[string]$Remote.ui.entry_class
        menu_label=[string]$Remote.ui.menu_label
        menu_group=[string]$Remote.ui.menu_group
        cache_view=[bool]$Remote.ui.cache_view
        single_window=$true
        synced_at=(Get-Date).ToString('o')
    }
    $integrationPath = Join-Path $Target 'platform_integration.json'
    $integration | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $integrationPath
    Action $Id 'UI_OK' "Embedded UI registered: $integrationPath"
    return $integrationPath
}
function Get-ModulePackage($Remote,[string]$Id){
    $version = [string]$Remote.version
    $package = Join-Path $downloadsDir ("{0}-{1}.zip" -f $Id,$version)
    $expectedHash = ([string]$Remote.package_sha256).ToLowerInvariant()
    $expectedSize = 0L
    try { $expectedSize = [int64]$Remote.package_size_bytes } catch {}

    if(Test-Path $package){
        $cachedSize = (Get-Item $package).Length
        $cachedHash = (Get-FileHash -Algorithm SHA256 -Path $package).Hash.ToLowerInvariant()
        if(((-not $expectedHash) -or $cachedHash -eq $expectedHash) -and (($expectedSize -le 0) -or $cachedSize -eq $expectedSize)){
            Action $Id 'PACKAGE_CACHE' "Valid cached package reused: size=$cachedSize sha256=$cachedHash"
            return $package
        }
        Action $Id 'PACKAGE_CACHE_INVALID' "Removing stale cache: size=$cachedSize sha256=$cachedHash"
        Remove-Item -Force $package -ErrorAction SilentlyContinue
    }

    $parts = @($Remote.package_parts)
    if($parts.Count -lt 1){ throw "Module manifest has no package_parts." }

    for($attempt=1; $attempt -le 2; $attempt++){
        $builder = New-Object System.Text.StringBuilder
        $i = 0
        foreach($part in $parts){
            $i++
            $url = Resolve-RawUrl ([string]$Remote._manifest_url) ([string]$part)
            $partFile = Join-Path $downloadsDir ("{0}-{1}-part{2:D2}.b64" -f $Id,$version,$i)
            Remove-Item -Force $partFile -ErrorAction SilentlyContinue
            Action $Id 'DOWNLOAD' "Package part $i/$($parts.Count), attempt $attempt/2"
            Download $url $partFile
            $partText = (Get-Content -Raw -Encoding UTF8 $partFile) -replace '\s',''
            if([string]::IsNullOrWhiteSpace($partText)){ throw "Downloaded package part is empty: $part" }
            [void]$builder.Append($partText)
        }

        try { [IO.File]::WriteAllBytes($package,[Convert]::FromBase64String($builder.ToString())) }
        catch { throw "Could not decode module package: $($_.Exception.Message)" }

        $actualSize = (Get-Item $package).Length
        $actualHash = (Get-FileHash -Algorithm SHA256 -Path $package).Hash.ToLowerInvariant()
        $sizeOk = ($expectedSize -le 0) -or ($actualSize -eq $expectedSize)
        $hashOk = (-not $expectedHash) -or ($actualHash -eq $expectedHash)

        if($sizeOk -and $hashOk){
            Action $Id 'PACKAGE_OK' "Size=$actualSize SHA-256=$actualHash"
            return $package
        }

        Action $Id 'PACKAGE_VERIFY_FAILED' "Attempt=$attempt ExpectedSize=$expectedSize ActualSize=$actualSize ExpectedSHA=$expectedHash ActualSHA=$actualHash"
        Remove-Item -Force $package -ErrorAction SilentlyContinue
        if($attempt -lt 2){
            Action $Id 'PACKAGE_RETRY' 'Verification failed; re-downloading every package part once.'
            Start-Sleep -Milliseconds 350
        }
    }

    throw "Module package verification failed after retry. ExpectedSize=$expectedSize ExpectedSHA=$expectedHash"
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
    $remote | Add-Member -NotePropertyName '_manifest_url' -NotePropertyValue $manifestUrl -Force
    $expectedVersion = [string]$remote.version
    $required = @($remote.required_files)
    $healthy = $installed -and (Test-RequiredFiles $target $required)
    $need = (-not $installed) -or (-not $healthy) -or ($installedVersion -ne $expectedVersion)

    if(-not $need){
        Action $id 'SKIP' "Already current and healthy. Version=$installedVersion"
        Ensure-Requirements $id (Join-Path $Root 'runtime\python\python.exe') (Join-Path $target ([string]$remote.requirements))
        $integration = Sync-EmbeddedIntegration $remote $target $id
        $launcher = Write-RootLauncher $target
        return [ordered]@{id=$id;status='ok';action='SKIP';installed=$true;version=$installedVersion;expected_version=$expectedVersion;path=$target;launcher=$launcher;integration=$integration;ui_mode=[string]$remote.ui.mode}
    }

    $action = if(-not $installed){'INSTALL'}elseif(-not $healthy){'REPAIR'}else{'UPDATE'}
    Action $id $action "Installed=$installedVersion Expected=$expectedVersion Healthy=$healthy"
    $package = Get-ModulePackage $remote $id

    $stage = Join-Path $stageRoot ($id + '_new')
    $backup = Join-Path $stageRoot ($id + '_preserved')
    $rollback = Join-Path $stageRoot ($id + '_rollback')
    Remove-Item -Recurse -Force $stage,$rollback -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $stage | Out-Null

    try {
        Expand-Archive -Path $package -DestinationPath $stage -Force
    } catch {
        Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
        Remove-Item -Force $package -ErrorAction SilentlyContinue
        throw "Module package archive is invalid: $($_.Exception.Message)"
    }
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
        $integration = Sync-EmbeddedIntegration $remote $target $id
        $launcher = Write-RootLauncher $target
        Remove-Item -Recurse -Force $rollback,$backup -ErrorAction SilentlyContinue
    } catch {
        Remove-Item -Recurse -Force $target -ErrorAction SilentlyContinue
        if(Test-Path $rollback){ Move-Item -Force $rollback $target }
        throw
    }

    Action $id 'OK' "Version=$expectedVersion Path=$target Launcher=$launcher Integration=$integration"
    [ordered]@{id=$id;status='ok';action=$action;installed=$true;version=$expectedVersion;expected_version=$expectedVersion;path=$target;launcher=$launcher;integration=$integration;ui_mode=[string]$remote.ui.mode}
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

    $summary = [ordered]@{schema_version=2;generated_at=(Get-Date).ToString('o');manager_version=$ManagerVersion;modules=$results}
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
