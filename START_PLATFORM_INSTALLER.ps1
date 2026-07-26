param(
    [string]$DefaultRoot = "D:\AutomationPlatform",
    [string]$ManifestUrl = "https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main/platform_manifest.json"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$RepoRawBase = "https://raw.githubusercontent.com/1777maxim7771/AutomationPlatform/main"
$InstallerCoreUrl = "$RepoRawBase/INSTALLER_CORE.ps1"

function Sanitize-Path([string]$PathValue) {
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return "" }
    $p = $PathValue.Trim()
    $p = $p.Trim([char]0x22, [char]0x27)
    $p = $p -replace '["'']', ''
    $p = $p.Trim()
    $p = $p.TrimEnd('.', ' ')
    return $p
}

function Test-ValidWindowsPath([string]$PathValue) {
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return $false }
    if ($PathValue -notmatch '^[A-Za-z]:[\\/]' -and $PathValue -notmatch '^\\\\[^\\]+\\[^\\]+') {
        return $false
    }
    $invalid = [System.IO.Path]::GetInvalidPathChars()
    foreach ($ch in $PathValue.ToCharArray()) {
        if ($invalid -contains $ch) { return $false }
        if ($ch -eq [char]0x22 -or $ch -eq [char]0x3C -or $ch -eq [char]0x3E -or $ch -eq [char]0x7C) { return $false }
    }
    return $true
}

function Get-LatestInstallerCore {
    param([string]$Destination)

    $dir = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    # Cache-bust raw.githubusercontent.com so UPDATE always gets current INSTALLER_CORE
    $url = $InstallerCoreUrl + "?nocache=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
    $resp = Invoke-WebRequest -UseBasicParsing -Uri $url
    $enc = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($Destination, $resp.Content, $enc)

    if (-not (Test-Path $Destination)) {
        throw "Failed to download INSTALLER_CORE.ps1 from GitHub."
    }
}

function Get-LatestLog([string]$Root) {
    $logDir = Join-Path $Root "logs"
    if (-not (Test-Path $logDir)) { return $null }
    $latest = Get-ChildItem $logDir -Filter "install_*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($latest) { return $latest.FullName }
    return $null
}

$DefaultRoot = Sanitize-Path $DefaultRoot
if ($DefaultRoot.EndsWith('\') -or $DefaultRoot.EndsWith('/')) {
    $DefaultRoot = $DefaultRoot.TrimEnd('\', '/')
}
if (-not $DefaultRoot) { $DefaultRoot = "D:\AutomationPlatform" }

$form = New-Object System.Windows.Forms.Form
$form.Text = "AutomationPlatform - Initial Setup / Update"
$form.Size = New-Object System.Drawing.Size(800, 640)
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
$sub.Text = "Install / update from GitHub (self-healing)"
$sub.ForeColor = [System.Drawing.Color]::LightGray
$sub.AutoSize = $true
$sub.Location = New-Object System.Drawing.Point(28, 58)
$form.Controls.Add($sub)

$labRoot = New-Object System.Windows.Forms.Label
$labRoot.Text = "Install root folder"
$labRoot.AutoSize = $true
$labRoot.Location = New-Object System.Drawing.Point(28, 100)
$form.Controls.Add($labRoot)

$txtRoot = New-Object System.Windows.Forms.TextBox
$txtRoot.Text = $DefaultRoot
$txtRoot.Location = New-Object System.Drawing.Point(28, 126)
$txtRoot.Size = New-Object System.Drawing.Size(720, 28)
$form.Controls.Add($txtRoot)

$labManifest = New-Object System.Windows.Forms.Label
$labManifest.Text = "GitHub Manifest URL"
$labManifest.AutoSize = $true
$labManifest.Location = New-Object System.Drawing.Point(28, 170)
$form.Controls.Add($labManifest)

$txtManifest = New-Object System.Windows.Forms.TextBox
$txtManifest.Text = $ManifestUrl
$txtManifest.Location = New-Object System.Drawing.Point(28, 196)
$txtManifest.Size = New-Object System.Drawing.Size(720, 28)
$form.Controls.Add($txtManifest)

$hint = New-Object System.Windows.Forms.Label
$hint.Text = "Each run downloads latest INSTALLER_CORE from GitHub (Python/tkinter/Chrome repair included)."
$hint.ForeColor = [System.Drawing.Color]::Gray
$hint.AutoSize = $true
$hint.Location = New-Object System.Drawing.Point(28, 228)
$form.Controls.Add($hint)

$cbPython = New-Object System.Windows.Forms.CheckBox
$cbPython.Text = "Local Python runtime (full + tkinter; repairs if missing)"
$cbPython.Checked = $true
$cbPython.AutoSize = $true
$cbPython.Location = New-Object System.Drawing.Point(32, 274)
$form.Controls.Add($cbPython)

$cbChrome = New-Object System.Windows.Forms.CheckBox
$cbChrome.Text = "Ensure official Google Chrome (required)"
$cbChrome.Checked = $true
$cbChrome.AutoSize = $true
$cbChrome.Location = New-Object System.Drawing.Point(32, 307)
$form.Controls.Add($cbChrome)

$cbProfile = New-Object System.Windows.Forms.CheckBox
$cbProfile.Text = "Create / keep Chrome_Profile"
$cbProfile.Checked = $true
$cbProfile.AutoSize = $true
$cbProfile.Location = New-Object System.Drawing.Point(32, 340)
$form.Controls.Add($cbProfile)

$cbControl = New-Object System.Windows.Forms.CheckBox
$cbControl.Text = "Install / update Control Center"
$cbControl.Checked = $true
$cbControl.AutoSize = $true
$cbControl.Location = New-Object System.Drawing.Point(32, 373)
$form.Controls.Add($cbControl)

$cbLaunch = New-Object System.Windows.Forms.CheckBox
$cbLaunch.Text = "Open Control Center after install"
$cbLaunch.Checked = $true
$cbLaunch.AutoSize = $true
$cbLaunch.Location = New-Object System.Drawing.Point(32, 406)
$form.Controls.Add($cbLaunch)

$status = New-Object System.Windows.Forms.Label
$status.Text = "Ready. Will download Installer Core from GitHub on start."
$status.ForeColor = [System.Drawing.Color]::LightGray
$status.AutoSize = $true
$status.Location = New-Object System.Drawing.Point(32, 458)
$form.Controls.Add($status)

$btn = New-Object System.Windows.Forms.Button
$btn.Text = "INSTALL / UPDATE"
$btn.Size = New-Object System.Drawing.Size(280, 46)
$btn.Location = New-Object System.Drawing.Point(468, 510)
$btn.BackColor = [System.Drawing.Color]::FromArgb(82,207,164)
$btn.ForeColor = [System.Drawing.Color]::Black
$btn.FlatStyle = "Flat"
$form.Controls.Add($btn)

$btn.Add_Click({
    try {
        $root = Sanitize-Path $txtRoot.Text
        $manifest = $txtManifest.Text.Trim().Trim([char]0x22, [char]0x27)
        $txtRoot.Text = $root

        if (-not $root) {
            [System.Windows.Forms.MessageBox]::Show("Specify install root folder.") | Out-Null
            return
        }
        if (-not (Test-ValidWindowsPath $root)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Invalid install path:`n$root`n`nUse e.g. D:\AutomationPlatform without quotes."
            ) | Out-Null
            return
        }
        if (-not $manifest) {
            [System.Windows.Forms.MessageBox]::Show("Specify platform_manifest.json URL.") | Out-Null
            return
        }

        New-Item -ItemType Directory -Force -Path $root | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $root "logs") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $root "installer") | Out-Null

        $tempDir = Join-Path $env:TEMP "AutomationPlatformBootstrap"
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
        $tempCore = Join-Path $tempDir "INSTALLER_CORE.ps1"

        $status.Text = "Downloading latest INSTALLER_CORE from GitHub..."
        $form.Refresh()
        Get-LatestInstallerCore -Destination $tempCore

        # Also keep a local copy under installer\
        Copy-Item -Force $tempCore (Join-Path $root "installer\INSTALLER_CORE.ps1")

        $argList = [System.Collections.Generic.List[string]]::new()
        $argList.Add("-NoProfile")
        $argList.Add("-ExecutionPolicy")
        $argList.Add("Bypass")
        $argList.Add("-File")
        $argList.Add($tempCore)
        $argList.Add("-Root")
        $argList.Add($root)
        $argList.Add("-ManifestUrl")
        $argList.Add($manifest)
        if ($cbPython.Checked)  { $argList.Add("-InstallPython") }
        if ($cbChrome.Checked)  { $argList.Add("-InstallChrome") }
        if ($cbControl.Checked) { $argList.Add("-InstallControlCenter") }
        if ($cbProfile.Checked) { $argList.Add("-CreateChromeProfile") }

        $status.Text = "Installing / repairing... watch the console window."
        $form.Refresh()

        $p = Start-Process -FilePath "powershell.exe" -ArgumentList $argList.ToArray() -Wait -PassThru

        $logPath = Get-LatestLog $root

        if ($p.ExitCode -ne 0) {
            $extra = ""
            if ($logPath) {
                $tail = Get-Content -Path $logPath -Tail 30 -ErrorAction SilentlyContinue
                $extra = "`n`nLog: $logPath`n`n" + ($tail -join "`n")
            }
            throw "Installer exited with code $($p.ExitCode).$extra"
        }

        $status.Text = "Install finished."

        if ($cbLaunch.Checked) {
            $launcher = Join-Path $root "START_CONTROL_CENTER.cmd"
            if (Test-Path $launcher) {
                Start-Process $launcher -WorkingDirectory $root
            }
        }

        $msg = "AutomationPlatform is ready.`n`nRoot: $root"
        if ($logPath) { $msg += "`nLog: $logPath" }
        [System.Windows.Forms.MessageBox]::Show($msg, "AutomationPlatform") | Out-Null
    }
    catch {
        $status.Text = "Error."
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "Install error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
})

[void]$form.ShowDialog()
