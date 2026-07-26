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

$btnLogs.Add_Click({
    $root = $txtRoot.Text.Trim().Trim([char]0x22,[char]0x27).TrimEnd('\','/')
    $logs = Join-Path $root "logs"
    New-Item -ItemType Directory -Force -Path $logs | Out-Null
    Start-Process explorer.exe $logs
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
        if ($rc -ne 0) { throw "Bootstrap failed with exit code $rc. See $root\logs\latest_bootstrap.log" }

        $status.Text = "Completed successfully."
        [System.Windows.Forms.MessageBox]::Show(
            "AutomationPlatform is ready.`n`nRoot: $root`nLogs: $root\logs",
            "AutomationPlatform"
        ) | Out-Null
    }
    catch {
        $status.Text = "ERROR"
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "AutomationPlatform error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
})

[void]$form.ShowDialog()
