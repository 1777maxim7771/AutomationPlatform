param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$ManifestUrl,
    [switch]$InstallDynamicConversationExporter
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ManagerVersion = "2026.07.27.6"

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
function Read-JsonFile([string]$Path){
    if(Test-Path $Path){ try { return (Get-Content -Raw -Encoding UTF8 $Path | ConvertFrom-Json) } catch { return $null } }
    return $null
}
function Get-InstalledVersion([string]$Target){
    $meta = Join-Path $Target 'module.json'
    if(-not(Test-Path $meta)){ return $null }
    try { return [string]((Get-Content -Raw -Encoding UTF8 $meta | ConvertFrom-Json).version) } catch { return $null }
}
function Test-RequiredFiles([string]$Base,$Required){
    foreach($rel in @($Required)){
        if(-not(Test-Path (Join-Path $Base ([string]$rel)))){ return $false }
    }
    return $true
}

# Windows PowerShell 5.1 turns native STDERR into NativeCommandError records.
# Native exit code is therefore authoritative; warnings on STDERR are logged only.
function Invoke-NativeLogged(
    [string]$FilePath,
    [object[]]$Arguments,
    [string]$Prefix,
    [switch]$Quiet
){
    if(-not(Test-Path $FilePath) -and $FilePath -notmatch '^[A-Za-z0-9_.-]+$'){
        throw "Native executable is missing: $FilePath"
    }
    $oldPreference = $ErrorActionPreference
    $captured = @()
    $exitCode = 1
    try {
        $ErrorActionPreference = 'Continue'
        $captured = @(& $FilePath @Arguments 2>&1)
        $exitCode = [int]$LASTEXITCODE
    } catch {
        $captured += $_.Exception.Message
        $exitCode = 1
    } finally {
        $ErrorActionPreference = $oldPreference
    }
    if(-not $Quiet){
        foreach($item in @($captured)){
            if($null -eq $item){ continue }
            $text = ([string]$item).TrimEnd()
            if($text){ Log ("[{0}] {1}" -f $Prefix,$text) }
        }
    }
    return $exitCode
}

function Test-DependencyImports([string]$PythonExe,$Imports){
    if(-not(Test-Path $PythonExe)){ return $false }
    $names = @($Imports | Where-Object { $_ -and ([string]$_).Trim() })
    if($names.Count -eq 0){ return $true }
    $code = (($names | ForEach-Object { "import " + ([string]$_).Trim() }) -join '; ')
    $rc = Invoke-NativeLogged -FilePath $PythonExe -Arguments @('-c',$code) -Prefix 'dependency-import' -Quiet
    return ($rc -eq 0)
}

function Test-ModuleSourceIntegrity(
    [string]$Id,
    [string]$Base,
    [string]$PythonExe,
    $ImportModules,
    [switch]$SkipImports
){
    Action $Id 'SOURCE_VALIDATE' "Base=$Base SkipImports=$([bool]$SkipImports)"
    if(-not(Test-Path $Base)){
        Action $Id 'SOURCE_INVALID' "Module directory is missing: $Base"
        return $false
    }
    if(-not(Test-Path $PythonExe)){
        Action $Id 'SOURCE_INVALID' "Platform Python is missing: $PythonExe"
        return $false
    }

    $pythonFiles = @(Get-ChildItem -Path $Base -Filter '*.py' -File -Recurse -ErrorAction SilentlyContinue)
    if($pythonFiles.Count -eq 0){
        Action $Id 'SOURCE_INVALID' 'No Python source files found.'
        return $false
    }

    foreach($file in $pythonFiles){
        try {
            $bytes = [IO.File]::ReadAllBytes($file.FullName)
            if($bytes -contains [byte]0){
                Action $Id 'SOURCE_INVALID' "NUL byte detected: $($file.FullName)"
                return $false
            }
        } catch {
            Action $Id 'SOURCE_INVALID' "Cannot read source file: $($file.FullName) :: $($_.Exception.Message)"
            return $false
        }
    }

    $compileRc = Invoke-NativeLogged -FilePath $PythonExe -Arguments @('-m','compileall','-q',$Base) -Prefix 'source-compile'
    if($compileRc -ne 0){
        Action $Id 'SOURCE_INVALID' "compileall failed. exit=$compileRc"
        return $false
    }

    if(-not $SkipImports){
        $names = @($ImportModules | Where-Object { $_ -and ([string]$_).Trim() })
        if($names.Count -gt 0){
            $escaped = $Base.Replace('\','\\').Replace("'","\\'")
            $imports = (($names | ForEach-Object { "import " + ([string]$_).Trim() }) -join '; ')
            $code = "import sys; sys.path.insert(0, r'$escaped'); $imports"
            $importRc = Invoke-NativeLogged -FilePath $PythonExe -Arguments @('-c',$code) -Prefix 'source-import'
            if($importRc -ne 0){
                Action $Id 'SOURCE_INVALID' "Module source import validation failed. exit=$importRc"
                return $false
            }
        }
    }

    Action $Id 'SOURCE_OK' "Python sources valid: files=$($pythonFiles.Count)"
    return $true
}

function Save-DependencyState([string]$Id,[string]$Hash){
    $state = Read-JsonFile $depsStatePath
    $all = [ordered]@{}
    if($state){ foreach($p in $state.PSObject.Properties){ $all[$p.Name] = $p.Value } }
    $all[$Id] = [ordered]@{
        requirements_sha256 = $Hash
        verified_at = (Get-Date).ToString('o')
        python = (Join-Path $Root 'runtime\python\python.exe')
        pip_check = 'ok'
    }
    $all | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $depsStatePath
}

function Ensure-Requirements([string]$Id,[string]$PythonExe,[string]$RequirementsPath,$Imports){
    if(-not(Test-Path $RequirementsPath)){
        Action $Id 'DEPENDENCIES_SKIP' 'requirements.txt is not present.'
        return
    }
    if(-not(Test-Path $PythonExe)){ throw "Platform-local Python is missing: $PythonExe" }

    $hash = (Get-FileHash -Algorithm SHA256 -Path $RequirementsPath).Hash.ToLowerInvariant()
    $state = Read-JsonFile $depsStatePath
    $oldHash = $null
    try { $oldHash = [string]$state.$Id.requirements_sha256 } catch {}

    $importsOk = Test-DependencyImports $PythonExe $Imports
    if($importsOk -and $oldHash -eq $hash){
        $checkRc = Invoke-NativeLogged -FilePath $PythonExe -Arguments @('-m','pip','check') -Prefix 'pip-check' -Quiet
        if($checkRc -eq 0){
            Action $Id 'DEPENDENCIES_SKIP' "Already healthy. requirements_sha256=$hash"
            return
        }
        Action $Id 'DEPENDENCIES_REPAIR' 'Recorded dependencies exist, but pip check reports a conflict. Repairing.'
    }

    Action $Id 'DEPENDENCIES_INSTALL' "Installing requirements with platform-local Python. hash=$hash"
    $pipArgs = @('-m','pip','install','--disable-pip-version-check','--no-warn-script-location','--upgrade-strategy','only-if-needed','-r',$RequirementsPath)
    $pipRc = Invoke-NativeLogged -FilePath $PythonExe -Arguments $pipArgs -Prefix 'pip'
    if($pipRc -ne 0){ throw "Python requirements installation failed for module $Id. pip exit code=$pipRc" }
    if(-not(Test-DependencyImports $PythonExe $Imports)){ throw "Module dependency import verification failed after pip install." }
    $checkRc = Invoke-NativeLogged -FilePath $PythonExe -Arguments @('-m','pip','check') -Prefix 'pip-check'
    if($checkRc -ne 0){ throw "Python dependency conflict detected after installing module $Id. pip check exit code=$checkRc" }
    Save-DependencyState $Id $hash
    Action $Id 'DEPENDENCIES_OK' 'Requirements installed; imports and pip check are healthy.'
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
    $pythonDir = Join-Path $Root 'runtime\python'
    $pythonExe = Join-Path $pythonDir 'python.exe'
    $pythonScripts = Join-Path $pythonDir 'Scripts'
    $main = Join-Path $Target 'main.py'
    $chromeLauncher = Join-Path $Root 'START_CHROME_DEBUG.cmd'
    $lines = @(
        '@echo off',
        'setlocal EnableExtensions',
        ('set "AUTOMATION_PLATFORM_ROOT={0}"' -f $Root),
        ('set "AUTOMATION_PLATFORM_MODULE_ROOT={0}"' -f $Target),
        'set "AUTOMATION_PLATFORM_MODULE_ID=dynamic_conversation_exporter"',
        ('set "AUTOMATION_PLATFORM_PYTHON={0}"' -f $pythonExe),
        ('set "AUTOMATION_PLATFORM_PROFILE={0}"' -f (Join-Path $Root 'browser\Chrome_Profile')),
        'set "AUTOMATION_PLATFORM_CDP_URL=http://127.0.0.1:9222"',
        'set "AUTOMATION_PLATFORM_CDP_PORT=9222"',
        ('set "PATH={0};{1};%PATH%"' -f $pythonScripts,$pythonDir),
        ('if not exist "{0}" (' -f $main),
        '  echo [ERROR] Dynamic Conversation Exporter is not installed.',
        '  pause',
        '  exit /b 1',
        ')',
        ('if exist "{0}" call "{0}" https://chatgpt.com/ >nul 2>&1' -f $chromeLauncher),
        ('cd /d "{0}"' -f $Target),
        ('"{0}" "{1}" --cdp "http://127.0.0.1:9222"' -f $pythonExe,$main),
        'exit /b %ERRORLEVEL%'
    )
    $lines | Set-Content -Encoding ASCII $launcher
    return $launcher
}

function Sync-EmbeddedIntegration($Remote,[string]$Target,[string]$Id){
    if(-not $Remote.ui){ Action $Id 'UI_SKIP' 'Remote manifest has no ui contract.'; return $null }
    if(([string]$Remote.ui.mode) -ne 'embedded'){ Action $Id 'UI_SKIP' "UI mode=$($Remote.ui.mode)"; return $null }
    $uiApi = [int]$Remote.ui.ui_api
    if($uiApi -gt 1){ throw "Module $Id requires unsupported embedded UI API $uiApi." }
    $source = [string]$Remote.ui.source
    $installedFile = [string]$Remote.ui.installed_file
    if(-not $installedFile){ $installedFile = $source }
    if(-not $source){ throw "Embedded UI source is missing in module manifest." }

    $sourceUrl = Resolve-RawUrl ([string]$Remote._manifest_url) $source
    $dest = Join-Path $Target $installedFile
    Action $Id 'UI_SYNC' "$source -> $dest"
    Download $sourceUrl $dest

    $python = Join-Path $Root 'runtime\python\python.exe'
    $compileRc = Invoke-NativeLogged -FilePath $python -Arguments @('-m','py_compile',$dest) -Prefix 'ui-py_compile'
    if($compileRc -ne 0){ throw "Embedded UI Python syntax validation failed for $Id." }

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
        if($sizeOk -and $hashOk){ Action $Id 'PACKAGE_OK' "Size=$actualSize SHA-256=$actualHash"; return $package }
        Action $Id 'PACKAGE_VERIFY_FAILED' "Attempt=$attempt ExpectedSize=$expectedSize ActualSize=$actualSize ExpectedSHA=$expectedHash ActualSHA=$actualHash"
        Remove-Item -Force $package -ErrorAction SilentlyContinue
        if($attempt -lt 2){ Action $Id 'PACKAGE_RETRY' 'Verification failed; re-downloading every package part once.'; Start-Sleep -Milliseconds 350 }
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
    $dependencyImports = @($remote.dependency_imports)
    if($dependencyImports.Count -eq 0){ $dependencyImports = @('playwright','markdownify','pyvda') }
    $sourceImports = @($remote.source_validation.import_modules)
    if($sourceImports.Count -eq 0){ $sourceImports = @('chatgpt_exporter.app','chatgpt_exporter.floating_panel','chatgpt_exporter.i18n','chatgpt_exporter.storage','embedded_panel') }
    $python = Join-Path $Root 'runtime\python\python.exe'

    $filesHealthy = $installed -and (Test-RequiredFiles $target $required)
    $sourceHealthy = $false
    if($filesHealthy){ $sourceHealthy = Test-ModuleSourceIntegrity $id $target $python $sourceImports }
    $healthy = $filesHealthy -and $sourceHealthy
    $need = (-not $installed) -or (-not $healthy) -or ($installedVersion -ne $expectedVersion)

    if(-not $need){
        Action $id 'SKIP' "Already current and source-healthy. Version=$installedVersion"
        Ensure-Requirements $id $python (Join-Path $target ([string]$remote.requirements)) $dependencyImports
        $integration = Sync-EmbeddedIntegration $remote $target $id
        if(-not(Test-ModuleSourceIntegrity $id $target $python $sourceImports)){ throw "Module became invalid after UI sync." }
        $launcher = Write-RootLauncher $target
        return [ordered]@{id=$id;status='ok';action='SKIP';installed=$true;version=$installedVersion;expected_version=$expectedVersion;path=$target;launcher=$launcher;integration=$integration;ui_mode=[string]$remote.ui.mode}
    }

    $action = if(-not $installed){'INSTALL'}elseif(-not $healthy){'REPAIR'}else{'UPDATE'}
    Action $id $action "Installed=$installedVersion Expected=$expectedVersion FilesHealthy=$filesHealthy SourceHealthy=$sourceHealthy"
    $package = Get-ModulePackage $remote $id

    $stage = Join-Path $stageRoot ($id + '_new')
    $backup = Join-Path $stageRoot ($id + '_preserved')
    $rollback = Join-Path $stageRoot ($id + '_rollback')
    Remove-Item -Recurse -Force $stage,$rollback -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    try { Expand-Archive -Path $package -DestinationPath $stage -Force }
    catch {
        Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
        Remove-Item -Force $package -ErrorAction SilentlyContinue
        throw "Module package archive is invalid: $($_.Exception.Message)"
    }
    if(-not(Test-RequiredFiles $stage $required)){
        Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
        throw "Staged module is incomplete; required files are missing."
    }
    if(-not(Test-ModuleSourceIntegrity $id $stage $python $sourceImports -SkipImports)){
        Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
        throw "Staged module source validation failed before dependency installation."
    }

    try {
        Ensure-Requirements $id $python (Join-Path $stage ([string]$remote.requirements)) $dependencyImports
        if(-not(Test-ModuleSourceIntegrity $id $stage $python $sourceImports)){ throw "Staged module import validation failed after dependency installation." }
    } catch {
        Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
        Action $id 'DEPENDENCIES_FAILED' 'Active module directory was not replaced.'
        throw
    }

    if($installed){ Copy-Preserved $target $backup @($remote.preserve_on_update) }
    if(Test-Path $target){ Move-Item -Force $target $rollback }
    try {
        Move-Item -Force $stage $target
        if(Test-Path $backup){ Restore-Preserved $backup $target @($remote.preserve_on_update) }
        if(-not(Test-RequiredFiles $target $required)){ throw "Installed module required-file verification failed." }
        $finalVersion = Get-InstalledVersion $target
        if($finalVersion -ne $expectedVersion){ throw "Installed module version mismatch. Expected=$expectedVersion Actual=$finalVersion" }
        $integration = Sync-EmbeddedIntegration $remote $target $id
        if(-not(Test-ModuleSourceIntegrity $id $target $python $sourceImports)){ throw "Final module source validation failed after activation/UI sync." }
        $launcher = Write-RootLauncher $target
        Remove-Item -Recurse -Force $rollback,$backup -ErrorAction SilentlyContinue
    } catch {
        Remove-Item -Recurse -Force $target -ErrorAction SilentlyContinue
        if(Test-Path $rollback){ Move-Item -Force $rollback $target }
        throw
    }

    Action $id 'OK' "Version=$expectedVersion Path=$target Launcher=$launcher Integration=$integration"
    return [ordered]@{id=$id;status='ok';action=$action;installed=$true;version=$expectedVersion;expected_version=$expectedVersion;path=$target;launcher=$launcher;integration=$integration;ui_mode=[string]$remote.ui.mode}
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
    $summary = [ordered]@{schema_version=4;generated_at=(Get-Date).ToString('o');manager_version=$ManagerVersion;overall_status='ok';modules=$results}
    $summary | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $statusPath
    Log "Status file: $statusPath"
    Copy-Item -Force $logFile $latestLog
    exit 0
} catch {
    $errorText = $_.Exception.Message
    Log "FATAL: $errorText" "ERROR"
    try { Log $_.ScriptStackTrace "ERROR" } catch {}
    try {
        $failure = [ordered]@{schema_version=4;generated_at=(Get-Date).ToString('o');manager_version=$ManagerVersion;overall_status='error';error=$errorText;modules=@()}
        $failure | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $statusPath
    } catch {}
    try { Copy-Item -Force $logFile $latestLog } catch {}
    exit 1
}
