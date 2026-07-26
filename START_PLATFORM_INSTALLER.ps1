param(
    [string]$DefaultRoot = "D:\AutomationPlatform",
    [string]$ManifestUrl = "https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/platform_manifest.json"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$RepoRaw = "https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main"

function Download-Runner([string]$Destination) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    $url = "$RepoRaw/BOOTSTRAP_RUNNER.ps1?nocache=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $Destination
    if (-not (Test-Path $Destination)) { throw "BOOTSTRAP_RUNNER.ps1 was not downloaded." }
}

function Get-LatestInstallLog([string]$Root) {
    $logDir = Join-Path $Root "logs"
    if (-not (Test-Path $logDir)) { return $null }
    return Get-ChildItem -Path $logDir -Filter "install_*.log" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Get-DiagnosticText([string]$Root) {
    $lines = New-Object System.Collections.Generic.List[string]
    $bootstrapLog = Join-Path $Root "logs\latest_bootstrap.log"
    if (Test-Path $bootstrapLog) {
        $lines.Add("BOOTSTRAP LOG: $bootstrapLog")
        $lines.Add("------------------------------------------------------------")
        foreach ($line in (Get-Content -Path $bootstrapLog -Tail 45 -ErrorAction SilentlyContinue)) {
            $lines.Add([string]$line)
        }
    } else {
        $lines.Add("Bootstrap log was not found: $bootstrapLog")
    }

    $installLog = Get-LatestInstallLog $Root
    if ($installLog) {
        $lines.Add("")
        $lines.Add("INSTALLER CORE LOG: $($installLog.FullName)")
        $lines.Add("------------------------------------------------------------")
        foreach ($line in (Get-Content -Path $installLog.FullName -Tail 55 -ErrorAction SilentlyContinue)) {
            $lines.Add([string]$line)
        }
    }

    return ($lines -join "`r`n")
}

function Show-Diagnostics([string]$Root, [string]$Title = "AutomationPlatform diagnostics") {
    $diag = Get-DiagnosticText $Root
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = $Title
    $dlg.Size = New-Object System.Drawing.Size(960, 680)
    $dlg.StartPosition = "CenterParent"
    $dlg.BackColor = [System.Drawing.Color]::FromArgb(18,24,32)
    $dlg.ForeColor = [System.Drawing.Color]::White

    $box = New-Object System.Windows.Forms.TextBox
    $box.Multiline = $true
    $box.ReadOnly = $true
    $box.ScrollBars = "Both"
    $box.WordWrap = $false
    $box.Font = New-Object System.Drawing.Font("Consolas", 9)
    $box.BackColor = [System.Drawing.Color]::FromArgb(10,14,20)
    $box.ForeColor = [System.Drawing.Color]::Gainsboro
    $box.Dock = "Fill"
    $box.Text = $diag
    $dlg.Controls.Add($box)

    [void]$dlg.ShowDialog()
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "AutomationPlatform - Install / Update / Repair"
$form.Size = New-Object System.Drawing.Size(800, 500)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(18,24,32)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)

$title = New-Object System.Windows.Forms.Label
$title.Text = "AutomationPlatform"
$title.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 18)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(24, 20)
$form.Controls.Add($title)

$sub = New-Object System.Windows.Forms.Label
$sub.Text = "One engine: check → skip / install / update / repair → health check"
$sub.ForeColor = [System.Drawing.Color]::LightGray
$sub.AutoSize = $true
$sub.Location = New-Object System.Drawing.Point(28, 58)
$form.Controls.Add($sub)

$labRoot = New-Object System.Windows.Forms.Label
$labRoot.Text = "Install root"
$labRoot.AutoSize = $true
$labRoot.Location = New-Object System.Drawing.Point(28, 105)
$form.Controls.Add($labRoot)

$txtRoot = New-Object System.Windows.Forms.TextBox
$txtRoot.Text = $DefaultRoot.Trim().TrimEnd('\','/')
$txtRoot.Location = New-Object System.Drawing.Point(28, 130)
$txtRoot.Size = New-Object System.Drawing.Size(720, 28)
$form.Controls.Add($txtRoot)

$labManifest = New-Object System.Windows.Forms.Label
$labManifest.Text = "GitHub Manifest"
$labManifest.AutoSize = $true
$labManifest.Location = New-Object System.Drawing.Point(28, 175)
$form.Controls.Add($labManifest)

$txtManifest = New-Object System.Windows.Forms.TextBox
$txtManifest.Text = $ManifestUrl
$txtManifest.Location = New-Object System.Drawing.Point(28, 200)
$txtManifest.Size = New-Object System.Drawing.Size(720, 28)
$form.Controls.Add($txtManifest)

$info = New-Object System.Windows.Forms.Label
$info.Text = "Healthy components are not reinstalled. Logs: <root>\logs. Status: <root>\data\platform_status.json"
$info.ForeColor = [System.Drawing.Color]::Gray
$info.AutoSize = $true
$info.Location = New-Object System.Drawing.Point(28, 245)
$form.Controls.Add($info)

$status = New-Object System.Windows.Forms.Label
$status.Text = "Ready"
$status.AutoSize = $true
$status.Location = New-Object System.Drawing.Point(28, 310)
$form.Controls.Add($status)

$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = "INSTALL / UPDATE / REPAIR"
$btnInstall.Size = New-Object System.Drawing.Size(290, 48)
$btnInstall.Location = New-Object System.Drawing.Point(458, 345)
$btnInstall.BackColor = [System.Drawing.Color]::FromArgb(82,207,164)
$btnInstall.ForeColor = [System.Drawing.Color]::Black
$btnInstall.FlatStyle = "Flat"
$form.Controls.Add($btnInstall)

$btnLogs = New-Object System.Windows.Forms.Button
$btnLogs.Text = "OPEN LOGS"
$btnLogs.Size = New-Object System.Drawing.Size(160, 40)
$btnLogs.Location = New-Object System.Drawing.Point(28, 350)
$form.Controls.Add($btnLogs)

$btnDiag = New-Object System.Windows.Forms.Button
$btnDiag.Text = "SHOW DIAGNOSTICS"
$btnDiag.Size = New-Object System.Drawing.Size(185, 40)
$btnDiag.Location = New-Object System.Drawing.Point(198, 350)
$form.Controls.Add($btnDiag)

$btnLogs.Add_Click({
    $root = $txtRoot.Text.Trim().Trim([char]0x22,[char]0x27).TrimEnd('\','/')
    $logs = Join-Path $root "logs"
    New-Item -ItemType Directory -Force -Path $logs | Out-Null
    Start-Process explorer.exe $logs
})

$btnDiag.Add_Click({
    $root = $txtRoot.Text.Trim().Trim([char]0x22,[char]0x27).TrimEnd('\','/')
    Show-Diagnostics $root
})

$btnInstall.Add_Click({
    try {
        $root = $txtRoot.Text.Trim().Trim([char]0x22,[char]0x27).TrimEnd('\','/')
        $manifest = $txtManifest.Text.Trim().Trim([char]0x22,[char]0x27)
        if (-not $root) { throw "Install root is empty." }
        if (-not $manifest) { throw "Manifest URL is empty." }

        New-Item -ItemType Directory -Force -Path $root | Out-Null
        $tempDir = Join-Path $env:TEMP "AutomationPlatform_Bootstrap"
        $runner = Join-Path $tempDir "BOOTSTRAP_RUNNER.ps1"
        $status.Text = "Downloading latest bootstrap runner..."
        $form.Refresh()
        Download-Runner $runner

        $status.Text = "Checking / installing / updating / repairing..."
        $form.Refresh()
        $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$runner,'-Root',$root,'-ManifestUrl',$manifest)
        & powershell.exe @args
        $rc = $LASTEXITCODE
        if ($rc -ne 0) {
            $status.Text = "ERROR - diagnostics opened"
            $summary = "Bootstrap failed with exit code $rc.`n`nDetailed diagnostics will open now.`n`nLog: $root\logs\latest_bootstrap.log"
            [System.Windows.Forms.MessageBox]::Show(
                $summary,
                "AutomationPlatform error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
            Show-Diagnostics $root "AutomationPlatform failure diagnostics"
            return
        }

        $status.Text = "Completed successfully."
        [System.Windows.Forms.MessageBox]::Show(
            "AutomationPlatform is ready.`n`nRoot: $root`nLogs: $root\logs",
            "AutomationPlatform"
        ) | Out-Null
    }
    catch {
        $status.Text = "ERROR"
        $root = $txtRoot.Text.Trim().Trim([char]0x22,[char]0x27).TrimEnd('\','/')
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "AutomationPlatform error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        if ($root -and (Test-Path (Join-Path $root 'logs'))) {
            Show-Diagnostics $root "AutomationPlatform exception diagnostics"
        }
    }
})

[void]$form.ShowDialog()
