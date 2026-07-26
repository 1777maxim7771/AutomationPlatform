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

function Get-LatestInstallerCore {
    param([string]$Destination)

    $dir = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    # Download as bytes and write UTF-8 with BOM so Windows PowerShell 5.1 parses Cyrillic correctly
    $bytes = (Invoke-WebRequest -UseBasicParsing -Uri $InstallerCoreUrl).Content
    if ($bytes -is [string]) {
        $enc = New-Object System.Text.UTF8Encoding $true
        [System.IO.File]::WriteAllText($Destination, $bytes, $enc)
    } else {
        [System.IO.File]::WriteAllBytes($Destination, $bytes)
    }

    if (-not (Test-Path $Destination)) {
        throw "Failed to download INSTALLER_CORE.ps1 from GitHub."
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "AutomationPlatform - Initial Setup / Update"
$form.Size = New-Object System.Drawing.Size(800, 625)
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
$sub.Text = "Install / update local platform"
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
$hint.Text = "Repository: github.com/1777maxim7771/AutomationPlatform"
$hint.ForeColor = [System.Drawing.Color]::Gray
$hint.AutoSize = $true
$hint.Location = New-Object System.Drawing.Point(28, 228)
$form.Controls.Add($hint)

$cbPython = New-Object System.Windows.Forms.CheckBox
$cbPython.Text = "Local Python runtime"
$cbPython.Checked = $true
$cbPython.AutoSize = $true
$cbPython.Location = New-Object System.Drawing.Point(32, 274)
$form.Controls.Add($cbPython)

$cbChrome = New-Object System.Windows.Forms.CheckBox
$cbChrome.Text = "Chrome for Testing / Debug runtime"
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
$status.Text = "Ready. Installer Core will be downloaded from GitHub."
$status.ForeColor = [System.Drawing.Color]::LightGray
$status.AutoSize = $true
$status.Location = New-Object System.Drawing.Point(32, 458)
$form.Controls.Add($status)

$btn = New-Object System.Windows.Forms.Button
$btn.Text = "INSTALL / UPDATE"
$btn.Size = New-Object System.Drawing.Size(280, 46)
$btn.Location = New-Object System.Drawing.Point(468, 500)
$btn.BackColor = [System.Drawing.Color]::FromArgb(82,207,164)
$btn.ForeColor = [System.Drawing.Color]::Black
$btn.FlatStyle = "Flat"
$form.Controls.Add($btn)

$btn.Add_Click({
    try {
        $root = $txtRoot.Text.Trim()
        $manifest = $txtManifest.Text.Trim()

        if (-not $root) {
            [System.Windows.Forms.MessageBox]::Show("Specify install root folder.") | Out-Null
            return
        }
        if (-not $manifest) {
            [System.Windows.Forms.MessageBox]::Show("Specify platform_manifest.json URL.") | Out-Null
            return
        }

        $tempCore = Join-Path $env:TEMP "AutomationPlatformBootstrap\INSTALLER_CORE.ps1"
        $status.Text = "Downloading Installer Core from GitHub..."
        $form.Refresh()
        Get-LatestInstallerCore -Destination $tempCore

        # Ensure core script is UTF-8 with BOM for WinPS 5.1
        try {
            $raw = [System.IO.File]::ReadAllText($tempCore)
            $utf8bom = New-Object System.Text.UTF8Encoding $true
            [System.IO.File]::WriteAllText($tempCore, $raw, $utf8bom)
        } catch {}

        $argList = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $tempCore,
            "-Root", $root,
            "-ManifestUrl", $manifest
        )
        if ($cbPython.Checked)  { $argList += "-InstallPython" }
        if ($cbChrome.Checked)  { $argList += "-InstallChrome" }
        if ($cbControl.Checked) { $argList += "-InstallControlCenter" }
        if ($cbProfile.Checked) { $argList += "-CreateChromeProfile" }

        $status.Text = "Installing... console window shows progress."
        $form.Refresh()

        $p = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -Wait -PassThru
        if ($p.ExitCode -ne 0) {
            throw "Installer exited with code $($p.ExitCode)."
        }

        $status.Text = "Install finished."

        if ($cbLaunch.Checked) {
            $launcher = Join-Path $root "START_CONTROL_CENTER.cmd"
            if (Test-Path $launcher) {
                Start-Process $launcher -WorkingDirectory $root
            }
        }

        [System.Windows.Forms.MessageBox]::Show(
            "AutomationPlatform is ready.`n`nRoot: $root",
            "AutomationPlatform"
        ) | Out-Null
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
