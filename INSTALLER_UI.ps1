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
$script:Proc = $null
$script:ExitCode = 0
$script:Pulse = $false

$buttonCode = @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
public class APGlowButton : Button {
    public Color BaseColor { get; set; }
    public Color HoverColor { get; set; }
    public Color PressColor { get; set; }
    public Color EdgeColor { get; set; }
    private bool over=false, down=false;
    public APGlowButton(){
        BaseColor=Color.FromArgb(37,181,151);
        HoverColor=Color.FromArgb(68,226,190);
        PressColor=Color.FromArgb(25,133,113);
        EdgeColor=Color.FromArgb(112,255,224);
        SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,true);
        FlatStyle=FlatStyle.Flat; FlatAppearance.BorderSize=0; Cursor=Cursors.Hand; ForeColor=Color.White;
    }
    private GraphicsPath Round(Rectangle r,int rad){
        GraphicsPath p=new GraphicsPath(); int d=rad*2;
        p.AddArc(r.X,r.Y,d,d,180,90); p.AddArc(r.Right-d,r.Y,d,d,270,90);
        p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90); p.AddArc(r.X,r.Bottom-d,d,d,90,90); p.CloseFigure(); return p;
    }
    protected override void OnPaint(PaintEventArgs e){
        e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
        Rectangle shadow=new Rectangle(2,5,Width-4,Height-8);
        using(GraphicsPath sp=Round(shadow,8)) using(SolidBrush sb=new SolidBrush(Color.FromArgb(80,0,0,0))) e.Graphics.FillPath(sb,sp);
        int y=down?4:1; Rectangle body=new Rectangle(2,y,Width-4,Height-8);
        Color c1=down?PressColor:(over?HoverColor:BaseColor);
        Color c2=Color.FromArgb(Math.Max(0,c1.R-18),Math.Max(0,c1.G-18),Math.Max(0,c1.B-18));
        using(GraphicsPath path=Round(body,8)){
            using(LinearGradientBrush br=new LinearGradientBrush(body,c1,c2,LinearGradientMode.Vertical)) e.Graphics.FillPath(br,path);
            using(Pen pen=new Pen(over?EdgeColor:Color.FromArgb(90,EdgeColor),over?2f:1f)) e.Graphics.DrawPath(pen,path);
        }
        Rectangle tr=new Rectangle(4,y,Width-8,Height-8);
        TextRenderer.DrawText(e.Graphics,Text,Font,tr,ForeColor,TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis);
    }
    protected override void OnMouseEnter(EventArgs e){over=true;Invalidate();base.OnMouseEnter(e);}
    protected override void OnMouseLeave(EventArgs e){over=false;down=false;Invalidate();base.OnMouseLeave(e);}
    protected override void OnMouseDown(MouseEventArgs e){down=true;Invalidate();base.OnMouseDown(e);}
    protected override void OnMouseUp(MouseEventArgs e){down=false;Invalidate();base.OnMouseUp(e);}
}
"@
try { Add-Type -TypeDefinition $buttonCode -ReferencedAssemblies @('System.Windows.Forms','System.Drawing') -ErrorAction SilentlyContinue } catch {}

function Download-Runner([string]$Destination) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    $url = "$RepoRaw/BOOTSTRAP_RUNNER.ps1?nocache=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $Destination
    if (-not (Test-Path $Destination)) { throw "BOOTSTRAP_RUNNER.ps1 was not downloaded." }
}
function Find-Chrome {
    foreach($p in @((Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),(Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe'))){if($p -and(Test-Path $p)){return $p}}
    return $null
}
function Get-LocalState([string]$Root) {
    $py=Join-Path $Root 'runtime\python\python.exe';$pv='not installed';$pyOk=$false
    if(Test-Path $py){try{$pv=(& $py -c "import sys;print('.'.join(map(str,sys.version_info[:3])))" 2>$null|Select-Object -First 1);& $py -c "import tkinter;import pip" 2>$null;$pyOk=($LASTEXITCODE -eq 0)}catch{}}
    $ch=Find-Chrome;$cv='not installed';if($ch){try{$cv=([string](Get-Item $ch).VersionInfo.ProductVersion).Trim()}catch{}}
    $cc='not installed';$cfg=Join-Path $Root 'config\platform.json';if(Test-Path $cfg){try{$cc=[string]((Get-Content -Raw -Encoding UTF8 $cfg|ConvertFrom-Json).control_center_version)}catch{}}
    $dcePath=Join-Path $Root 'modules\dynamic_conversation_exporter\module.json';$dce=$null
    if(Test-Path $dcePath){try{$dce=[string]((Get-Content -Raw -Encoding UTF8 $dcePath|ConvertFrom-Json).version)}catch{$dce='installed'}}
    return @{Python=$pv;PythonOk=$pyOk;Chrome=$cv;ChromeOk=[bool]$ch;CC=$cc;CCOk=($cc -ne 'not installed');DCE=$dce;DCEInstalled=[bool]$dce}
}
function Tail([string]$Path,[int]$Count=18){if(Test-Path $Path){return((Get-Content -Path $Path -Tail $Count -ErrorAction SilentlyContinue)-join "`r`n")};return "Waiting for live bootstrap log..."}
function Set-Card($Panel,$Dot,$Value,[string]$State){
    $Value.Text=$State
    if($State -match 'OK|healthy|SKIP|PREVERIFIED|CURRENT'){$Dot.BackColor=[Drawing.Color]::FromArgb(66,235,174);$Panel.BackColor=[Drawing.Color]::FromArgb(22,48,46)}
    elseif($State -match 'WARN|DEFER|UPDATE'){$Dot.BackColor=[Drawing.Color]::FromArgb(255,190,67);$Panel.BackColor=[Drawing.Color]::FromArgb(52,43,23)}
    elseif($State -match 'ERROR|FATAL|missing|not installed'){$Dot.BackColor=[Drawing.Color]::FromArgb(255,91,91);$Panel.BackColor=[Drawing.Color]::FromArgb(55,28,33)}
    else{$Dot.BackColor=[Drawing.Color]::FromArgb(80,145,185);$Panel.BackColor=[Drawing.Color]::FromArgb(25,38,51)}
}

$form=New-Object System.Windows.Forms.Form
$form.Text='AutomationPlatform - Smart Install / Update / Repair'
$form.Size=New-Object System.Drawing.Size(980,760)
$form.MinimumSize=New-Object System.Drawing.Size(900,700)
$form.StartPosition='CenterScreen'
$form.BackColor=[Drawing.Color]::FromArgb(10,17,26)
$form.ForeColor=[Drawing.Color]::White
$form.Font=New-Object Drawing.Font('Segoe UI',10)

$header=New-Object Windows.Forms.Panel;$header.Dock='Top';$header.Height=104;$header.BackColor=[Drawing.Color]::FromArgb(13,25,38);$form.Controls.Add($header)
$title=New-Object Windows.Forms.Label;$title.Text='AutomationPlatform';$title.Font=New-Object Drawing.Font('Segoe UI Semibold',22);$title.ForeColor=[Drawing.Color]::FromArgb(239,249,255);$title.AutoSize=$true;$title.Location=New-Object Drawing.Point(28,18);$header.Controls.Add($title)
$sub=New-Object Windows.Forms.Label;$sub.Text='SELF-UPDATING  |  CHECK -> SKIP / INSTALL / UPDATE / REPAIR -> HEALTH';$sub.Font=New-Object Drawing.Font('Segoe UI',9);$sub.ForeColor=[Drawing.Color]::FromArgb(76,220,190);$sub.AutoSize=$true;$sub.Location=New-Object Drawing.Point(31,61);$header.Controls.Add($sub)
$badge=New-Object Windows.Forms.Label;$badge.Text='GITHUB LIVE';$badge.TextAlign='MiddleCenter';$badge.Font=New-Object Drawing.Font('Segoe UI Semibold',9);$badge.Size=New-Object Drawing.Size(116,30);$badge.Anchor='Top,Right';$badge.Location=New-Object Drawing.Point(820,27);$badge.BackColor=[Drawing.Color]::FromArgb(24,60,57);$badge.ForeColor=[Drawing.Color]::FromArgb(94,255,210);$header.Controls.Add($badge)

$rootLabel=New-Object Windows.Forms.Label;$rootLabel.Text='Install root';$rootLabel.AutoSize=$true;$rootLabel.Location=New-Object Drawing.Point(28,122);$form.Controls.Add($rootLabel)
$txtRoot=New-Object Windows.Forms.TextBox;$txtRoot.Text=$DefaultRoot.Trim().TrimEnd('\','/');$txtRoot.Location=New-Object Drawing.Point(28,146);$txtRoot.Size=New-Object Drawing.Size(650,28);$txtRoot.Anchor='Top,Left,Right';$txtRoot.BackColor=[Drawing.Color]::FromArgb(235,242,246);$form.Controls.Add($txtRoot)

$btnAdvanced=New-Object APGlowButton;$btnAdvanced.Text='ADVANCED';$btnAdvanced.Size=New-Object Drawing.Size(124,38);$btnAdvanced.Location=New-Object Drawing.Point(694,141);$btnAdvanced.Anchor='Top,Right';$btnAdvanced.BaseColor=[Drawing.Color]::FromArgb(42,79,112);$btnAdvanced.HoverColor=[Drawing.Color]::FromArgb(65,119,166);$btnAdvanced.EdgeColor=[Drawing.Color]::FromArgb(100,184,245);$form.Controls.Add($btnAdvanced)
$btnRefresh=New-Object APGlowButton;$btnRefresh.Text='RESCAN';$btnRefresh.Size=New-Object Drawing.Size(116,38);$btnRefresh.Location=New-Object Drawing.Point(826,141);$btnRefresh.Anchor='Top,Right';$btnRefresh.BaseColor=[Drawing.Color]::FromArgb(42,79,112);$btnRefresh.HoverColor=[Drawing.Color]::FromArgb(65,119,166);$btnRefresh.EdgeColor=[Drawing.Color]::FromArgb(100,184,245);$form.Controls.Add($btnRefresh)

$modulePanel=New-Object Windows.Forms.Panel;$modulePanel.Location=New-Object Drawing.Point(28,190);$modulePanel.Size=New-Object Drawing.Size(914,50);$modulePanel.Anchor='Top,Left,Right';$modulePanel.BackColor=[Drawing.Color]::FromArgb(17,32,45);$form.Controls.Add($modulePanel)
$moduleLabel=New-Object Windows.Forms.Label;$moduleLabel.Text='OPTIONAL MODULE';$moduleLabel.Font=New-Object Drawing.Font('Segoe UI Semibold',9);$moduleLabel.ForeColor=[Drawing.Color]::FromArgb(93,219,240);$moduleLabel.AutoSize=$true;$moduleLabel.Location=New-Object Drawing.Point(12,7);$modulePanel.Controls.Add($moduleLabel)
$chkDce=New-Object Windows.Forms.CheckBox;$chkDce.Text='Dynamic Conversation Exporter v1.6  -  Partial pairs / attachments / ChatGPT CDP';$chkDce.AutoSize=$true;$chkDce.Location=New-Object Drawing.Point(12,25);$chkDce.ForeColor=[Drawing.Color]::FromArgb(225,239,246);$chkDce.BackColor=$modulePanel.BackColor;$modulePanel.Controls.Add($chkDce)
$dceState=New-Object Windows.Forms.Label;$dceState.Text='optional - not installed';$dceState.AutoSize=$true;$dceState.Anchor='Top,Right';$dceState.Location=New-Object Drawing.Point(710,26);$dceState.ForeColor=[Drawing.Color]::FromArgb(170,192,207);$modulePanel.Controls.Add($dceState)

$advanced=New-Object Windows.Forms.Panel;$advanced.Location=New-Object Drawing.Point(28,246);$advanced.Size=New-Object Drawing.Size(914,52);$advanced.Anchor='Top,Left,Right';$advanced.Visible=$false;$advanced.BackColor=[Drawing.Color]::FromArgb(16,28,40);$form.Controls.Add($advanced)
$manifestLabel=New-Object Windows.Forms.Label;$manifestLabel.Text='GitHub Manifest';$manifestLabel.AutoSize=$true;$manifestLabel.Location=New-Object Drawing.Point(10,5);$advanced.Controls.Add($manifestLabel)
$txtManifest=New-Object Windows.Forms.TextBox;$txtManifest.Text=$ManifestUrl;$txtManifest.Location=New-Object Drawing.Point(10,25);$txtManifest.Size=New-Object Drawing.Size(890,24);$txtManifest.Anchor='Top,Left,Right';$advanced.Controls.Add($txtManifest)

function New-StatusCard([int]$X,[string]$Name){
    $p=New-Object Windows.Forms.Panel;$p.Size=New-Object Drawing.Size(286,70);$p.Location=New-Object Drawing.Point($X,310);$p.BackColor=[Drawing.Color]::FromArgb(25,38,51);$form.Controls.Add($p)
    $d=New-Object Windows.Forms.Panel;$d.Size=New-Object Drawing.Size(12,12);$d.Location=New-Object Drawing.Point(14,16);$d.BackColor=[Drawing.Color]::FromArgb(80,145,185);$p.Controls.Add($d)
    $n=New-Object Windows.Forms.Label;$n.Text=$Name;$n.Font=New-Object Drawing.Font('Segoe UI Semibold',10);$n.AutoSize=$true;$n.Location=New-Object Drawing.Point(34,11);$p.Controls.Add($n)
    $v=New-Object Windows.Forms.Label;$v.Text='checking...';$v.ForeColor=[Drawing.Color]::FromArgb(170,192,207);$v.AutoSize=$true;$v.Location=New-Object Drawing.Point(14,40);$p.Controls.Add($v)
    return @($p,$d,$v)
}
$pyCard=New-StatusCard 28 'PYTHON RUNTIME';$chCard=New-StatusCard 337 'GOOGLE CHROME';$ccCard=New-StatusCard 646 'CONTROL CENTER'

$progressOuter=New-Object Windows.Forms.Panel;$progressOuter.Location=New-Object Drawing.Point(28,396);$progressOuter.Size=New-Object Drawing.Size(914,16);$progressOuter.Anchor='Top,Left,Right';$progressOuter.BackColor=[Drawing.Color]::FromArgb(28,41,53);$form.Controls.Add($progressOuter)
$progressFill=New-Object Windows.Forms.Panel;$progressFill.Location=New-Object Drawing.Point(0,0);$progressFill.Size=New-Object Drawing.Size(2,16);$progressFill.BackColor=[Drawing.Color]::FromArgb(72,224,185);$progressOuter.Controls.Add($progressFill)
$phase=New-Object Windows.Forms.Label;$phase.Text='Ready - local health scan';$phase.AutoSize=$true;$phase.Location=New-Object Drawing.Point(28,421);$phase.ForeColor=[Drawing.Color]::FromArgb(170,192,207);$form.Controls.Add($phase)

$logBox=New-Object Windows.Forms.TextBox;$logBox.Multiline=$true;$logBox.ReadOnly=$true;$logBox.ScrollBars='Vertical';$logBox.WordWrap=$false;$logBox.Font=New-Object Drawing.Font('Consolas',9);$logBox.BackColor=[Drawing.Color]::FromArgb(6,12,18);$logBox.ForeColor=[Drawing.Color]::FromArgb(183,214,226);$logBox.Location=New-Object Drawing.Point(28,451);$logBox.Size=New-Object Drawing.Size(914,178);$logBox.Anchor='Top,Bottom,Left,Right';$logBox.Text='Live bootstrap output will appear here.';$form.Controls.Add($logBox)

$btnLogs=New-Object APGlowButton;$btnLogs.Text='OPEN LOGS';$btnLogs.Size=New-Object Drawing.Size(140,44);$btnLogs.Location=New-Object Drawing.Point(28,654);$btnLogs.Anchor='Bottom,Left';$btnLogs.BaseColor=[Drawing.Color]::FromArgb(43,74,101);$btnLogs.HoverColor=[Drawing.Color]::FromArgb(62,111,151);$btnLogs.EdgeColor=[Drawing.Color]::FromArgb(110,184,235);$form.Controls.Add($btnLogs)
$btnInstall=New-Object APGlowButton;$btnInstall.Text='INSTALL / UPDATE / REPAIR';$btnInstall.Size=New-Object Drawing.Size(320,52);$btnInstall.Location=New-Object Drawing.Point(622,648);$btnInstall.Anchor='Bottom,Right';$btnInstall.Font=New-Object Drawing.Font('Segoe UI Semibold',10);$form.Controls.Add($btnInstall)
$status=New-Object Windows.Forms.Label;$status.Text='READY';$status.AutoSize=$true;$status.Location=New-Object Drawing.Point(185,668);$status.Anchor='Bottom,Left';$status.ForeColor=[Drawing.Color]::FromArgb(91,229,192);$form.Controls.Add($status)

function Update-LocalCards {
    $root=$txtRoot.Text.Trim().Trim([char]0x22,[char]0x27).TrimEnd('\','/')
    $s=Get-LocalState $root
    if($s.PythonOk){Set-Card $pyCard[0] $pyCard[1] $pyCard[2] "OK  $($s.Python)"}else{Set-Card $pyCard[0] $pyCard[1] $pyCard[2] $s.Python}
    if($s.ChromeOk){Set-Card $chCard[0] $chCard[1] $chCard[2] "OK  $($s.Chrome)"}else{Set-Card $chCard[0] $chCard[1] $chCard[2] $s.Chrome}
    if($s.CCOk){Set-Card $ccCard[0] $ccCard[1] $ccCard[2] "OK  v$($s.CC)"}else{Set-Card $ccCard[0] $ccCard[1] $ccCard[2] $s.CC}
    if($s.DCEInstalled){$chkDce.Checked=$true;$dceState.Text="INSTALLED  v$($s.DCE)  - auto-update";$dceState.ForeColor=[Drawing.Color]::FromArgb(91,229,192)}else{$dceState.Text='OPTIONAL - not installed';$dceState.ForeColor=[Drawing.Color]::FromArgb(170,192,207)}
}
function Set-Progress([int]$Pct){$pct=[Math]::Max(0,[Math]::Min(100,$Pct));$w=[int](($progressOuter.ClientSize.Width*$pct)/100);if($w -lt 2){$w=2};$progressFill.Width=$w}
function Parse-Live([string]$Text){
    if($Text -match 'PHASE 1/5'){Set-Progress 15;$phase.Text='PHASE 1/5  |  Python runtime'}
    if($Text -match 'PHASE 2/5'){Set-Progress 32;$phase.Text='PHASE 2/5  |  Chrome runtime'}
    if($Text -match 'PHASE 3/5'){Set-Progress 50;$phase.Text='PHASE 3/5  |  Control Center package'}
    if($Text -match 'PHASE 4/5'){Set-Progress 68;$phase.Text='PHASE 4/5  |  Finalize platform'}
    if($Text -match 'PHASE 5/5'){Set-Progress 84;$phase.Text='PHASE 5/5  |  Optional modules'}
    if($Text -match '\[PYTHON\]\[(SKIP|OK|PREVERIFIED)\]'){Set-Card $pyCard[0] $pyCard[1] $pyCard[2] 'OK / SKIP'}
    if($Text -match '\[CHROME\]\[(SKIP|OK|PREVERIFIED)\]'){Set-Card $chCard[0] $chCard[1] $chCard[2] 'OK / SKIP'}
    if($Text -match '\[CHROME\]\[(DEFER_UPDATE|UPDATE_FAILED_USING_EXISTING)\]'){Set-Card $chCard[0] $chCard[1] $chCard[2] 'WARN / DEFER'}
    if($Text -match '\[CONTROL_CENTER\]\[(OK|SKIP)\]'){Set-Card $ccCard[0] $ccCard[1] $ccCard[2] 'OK / CURRENT'}
    if($Text -match '\[MODULE:dynamic_conversation_exporter\]\[(INSTALL|UPDATE|REPAIR)\]'){$dceState.Text='INSTALLING / UPDATING...';$dceState.ForeColor=[Drawing.Color]::FromArgb(255,198,78)}
    if($Text -match '\[MODULE:dynamic_conversation_exporter\]\[OK\]'){$dceState.Text='INSTALLED / READY';$dceState.ForeColor=[Drawing.Color]::FromArgb(91,229,192)}
    if($Text -match 'Bootstrap completed successfully'){Set-Progress 100;$phase.Text='COMPLETE  |  Health check passed'}
    if($Text -match 'FATAL:'){$phase.Text='ERROR  |  See live diagnostics';$phase.ForeColor=[Drawing.Color]::FromArgb(255,100,100)}
}

$timer=New-Object Windows.Forms.Timer;$timer.Interval=300
$timer.Add_Tick({
    $root=$txtRoot.Text.Trim().Trim([char]0x22,[char]0x27).TrimEnd('\','/');$live=Join-Path $root 'logs\latest_bootstrap.log';$text=Tail $live 18
    if($logBox.Text -ne $text){$logBox.Text=$text;$logBox.SelectionStart=$logBox.TextLength;$logBox.ScrollToCaret();Parse-Live $text}
    if($script:Proc -and $script:Proc.HasExited){
        $timer.Stop();$rc=$script:Proc.ExitCode;$script:Proc=$null;$btnInstall.Enabled=$true
        if($rc -eq 0){Set-Progress 100;$status.Text='SUCCESS';$status.ForeColor=[Drawing.Color]::FromArgb(91,229,192);$phase.Text='Platform ready';Update-LocalCards;$btnInstall.Text='RUN AGAIN / CHECK UPDATES'}
        else{$status.Text="ERROR $rc";$status.ForeColor=[Drawing.Color]::FromArgb(255,100,100);$phase.Text='Operation failed - diagnostics are shown above';$script:ExitCode=$rc}
    }
})
$pulse=New-Object Windows.Forms.Timer;$pulse.Interval=700
$pulse.Add_Tick({if(-not $script:Proc){$script:Pulse=-not $script:Pulse;if($script:Pulse){$btnInstall.EdgeColor=[Drawing.Color]::FromArgb(150,255,225)}else{$btnInstall.EdgeColor=[Drawing.Color]::FromArgb(80,220,190)};$btnInstall.Invalidate()}});$pulse.Start()

$btnAdvanced.Add_Click({$advanced.Visible=-not $advanced.Visible})
$btnRefresh.Add_Click({Update-LocalCards;$status.Text='RESCANNED'})
$btnLogs.Add_Click({$r=$txtRoot.Text.Trim().Trim([char]0x22,[char]0x27).TrimEnd('\','/');$p=Join-Path $r 'logs';New-Item -ItemType Directory -Force -Path $p|Out-Null;Start-Process explorer.exe $p})
$btnInstall.Add_Click({
    if($script:Proc){return}
    try{
        $root=$txtRoot.Text.Trim().Trim([char]0x22,[char]0x27).TrimEnd('\','/');$manifest=$txtManifest.Text.Trim().Trim([char]0x22,[char]0x27)
        if(-not $root){throw 'Install root is empty.'};if(-not $manifest){throw 'Manifest URL is empty.'}
        New-Item -ItemType Directory -Force -Path $root,(Join-Path $root 'logs')|Out-Null
        $tempDir=Join-Path $env:TEMP 'AutomationPlatform_Bootstrap';$runner=Join-Path $tempDir 'BOOTSTRAP_RUNNER.ps1'
        $status.Text='SYNCING GITHUB';$phase.Text='Downloading latest bootstrap engine...';Set-Progress 5;$form.Refresh();Download-Runner $runner
        $args="-NoProfile -ExecutionPolicy Bypass -File `"$runner`" -Root `"$root`" -ManifestUrl `"$manifest`""
        if($chkDce.Checked){$args += ' -InstallDynamicConversationExporter'}
        $psi=New-Object System.Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.Arguments=$args;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.WorkingDirectory=$root
        $script:Proc=New-Object System.Diagnostics.Process;$script:Proc.StartInfo=$psi;[void]$script:Proc.Start()
        $btnInstall.Enabled=$false;$btnInstall.Text='WORKING...';$status.Text='RUNNING';$status.ForeColor=[Drawing.Color]::FromArgb(255,198,78);$phase.ForeColor=[Drawing.Color]::FromArgb(170,192,207);$timer.Start()
    }catch{$status.Text='ERROR';$status.ForeColor=[Drawing.Color]::FromArgb(255,100,100);[Windows.Forms.MessageBox]::Show($_.Exception.Message,'AutomationPlatform error',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)|Out-Null}
})
$form.Add_Shown({Update-LocalCards})
$form.Add_FormClosing({if($script:Proc -and -not $script:Proc.HasExited){$answer=[Windows.Forms.MessageBox]::Show('An install/update operation is still running. Close the panel anyway?','AutomationPlatform',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning);if($answer -ne [Windows.Forms.DialogResult]::Yes){$_.Cancel=$true}}})

[void]$form.ShowDialog()
exit $script:ExitCode
