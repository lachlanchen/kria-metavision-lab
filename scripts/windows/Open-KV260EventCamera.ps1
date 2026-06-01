[CmdletBinding()]
param(
    [string]$HostAlias = "petalinux-kv260",
    [string]$RemoteProject = "/home/petalinux/Projects/kria-kv260-starter",
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"
$InstallDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BoardScript = Join-Path $InstallDir "Start-KV260EventCamera-BoardDesktop.ps1"
$X11Script = Join-Path $InstallDir "Start-KV260EventCamera-X11.ps1"
$LogDir = Join-Path $env:TEMP "kv260-event-camera"
$JupyterLocalPort = 8888
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Get-SshExe {
    return (Get-Command ssh.exe -ErrorAction Stop).Source
}

function Invoke-KV260Ssh {
    param([string]$RemoteCommand)
    $ssh = Get-SshExe
    $output = & $ssh -o BatchMode=yes $HostAlias $RemoteCommand 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        throw "ssh exited with code $code`r`n$output"
    }
    return ($output -join "`r`n")
}

if ($CheckOnly) {
    $required = @(
        $BoardScript,
        $X11Script,
        (Join-Path $InstallDir "Start-KV260EventCamera-X11.ps1")
    )
    $missing = $required | Where-Object { -not (Test-Path $_) }
    if ($missing) {
        Write-Host "MISSING=$($missing -join ',')"
        exit 1
    }
    Write-Host "SSH=$(Get-SshExe)"
    Write-Host "BOARD_SCRIPT=$BoardScript"
    Write-Host "X11_SCRIPT=$X11Script"
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Add-Log {
    param([string]$Text)
    $timestamp = Get-Date -Format "HH:mm:ss"
    $script:OutputBox.AppendText("[$timestamp] $Text`r`n")
}

function Show-Message {
    param([string]$Text, [string]$Title = "KV260 Control Center")
    [System.Windows.Forms.MessageBox]::Show($Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

function Confirm-Action {
    param([string]$Text)
    $result = [System.Windows.Forms.MessageBox]::Show($Text, "KV260 Control Center", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    return $result -eq [System.Windows.Forms.DialogResult]::Yes
}

function Ensure-VcXsrv {
    $programFilesX86 = [Environment]::GetFolderPath("ProgramFilesX86")
    $candidates = @(
        (Join-Path $env:ProgramFiles "VcXsrv\vcxsrv.exe"),
        (Join-Path $programFilesX86 "VcXsrv\vcxsrv.exe")
    )
    $vcxsrv = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $vcxsrv) {
        throw "VcXsrv is not installed. Install VcXsrv, then try again."
    }
    if (-not (Get-Process -Name vcxsrv -ErrorAction SilentlyContinue)) {
        Start-Process -FilePath $vcxsrv -ArgumentList @(":0", "-multiwindow", "-clipboard", "-wgl", "-ac")
        Start-Sleep -Seconds 2
    }
    $env:DISPLAY = "localhost:0.0"
    return $vcxsrv
}

function Start-RemoteX11Command {
    param([string]$RemoteCommand, [string]$LogName)
    Ensure-VcXsrv | Out-Null
    $ssh = Get-SshExe
    $logFile = Join-Path $LogDir $LogName
    "[$(Get-Date -Format s)] ssh -Y $HostAlias $RemoteCommand" | Out-File -FilePath $logFile -Append -Encoding utf8
    Start-Process `
        -FilePath $ssh `
        -ArgumentList @("-q", "-Y", "-o", "ForwardX11Trusted=yes", "-o", "BatchMode=yes", $HostAlias, $RemoteCommand) `
        -WindowStyle Hidden
}

function Refresh-Status {
    try {
        $camera = Invoke-KV260Ssh "cd $RemoteProject && ./scripts/kv260-event-camera-switch.sh --status"
        $apps = Invoke-KV260Ssh "cd $RemoteProject && ./scripts/kv260-remote-gui-app.sh --list"
        $jupyter = Invoke-KV260Ssh "cd $RemoteProject && ./scripts/kv260-jupyter-notebook.sh --status"
        $vcxsrv = if (Get-Process -Name vcxsrv -ErrorAction SilentlyContinue) { "running" } else { "not running" }
        Add-Log "Status:`r`n$camera`r`n$jupyter`r`nVcXsrv: $vcxsrv`r`nApps:`r`n$apps"
    } catch {
        Add-Log "Status failed: $($_.Exception.Message)"
    }
}

function Start-BoardDesktop {
    try {
        Add-Log "Switching camera to KV260 display..."
        & $BoardScript -HostAlias $HostAlias -RemoteProject $RemoteProject
        Add-Log "Requested KV260 display mode. The GUI should appear on the board monitor."
        Refresh-Status
    } catch {
        Add-Log "Board display launch failed: $($_.Exception.Message)"
    }
}

function Start-WindowsX11 {
    try {
        Add-Log "Switching camera to Windows X11..."
        & $X11Script -HostAlias $HostAlias -RemoteProject $RemoteProject
        Add-Log "Requested Windows X11 mode. The GUI should appear on this Windows desktop."
        Refresh-Status
    } catch {
        Add-Log "Windows X11 launch failed: $($_.Exception.Message)"
    }
}

function Stop-AllViewers {
    try {
        Add-Log "Stopping all camera viewers..."
        $result = Invoke-KV260Ssh "cd $RemoteProject && ./scripts/kv260-event-camera-switch.sh --stop-all && ./scripts/kv260-event-camera-switch.sh --status"
        Add-Log $result
    } catch {
        Add-Log "Stop failed: $($_.Exception.Message)"
    }
}

function Open-RemoteApp {
    param([string]$AppId, [string]$Label)
    try {
        Add-Log "Opening $Label through SSH X11..."
        $check = Invoke-KV260Ssh "cd $RemoteProject && ./scripts/kv260-remote-gui-app.sh --check $AppId"
        Add-Log $check
        Start-RemoteX11Command "cd $RemoteProject && ./scripts/kv260-remote-gui-app.sh --launch $AppId" "x11-app-$AppId.log"
    } catch {
        Add-Log "Could not open ${Label}: $($_.Exception.Message)"
    }
}

function Get-TunnelProcesses {
    Get-CimInstance Win32_Process -Filter "Name = 'ssh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*-L ${JupyterLocalPort}:127.0.0.1:8888*" -and $_.CommandLine -like "*$HostAlias*" }
}

function Start-Jupyter {
    try {
        Add-Log "Starting Jupyter on KV260..."
        $server = Invoke-KV260Ssh "cd $RemoteProject && ./scripts/kv260-jupyter-notebook.sh --start"
        Add-Log $server

        if (-not (Get-TunnelProcesses)) {
            $ssh = Get-SshExe
            Start-Process `
                -FilePath $ssh `
                -ArgumentList @("-q", "-N", "-L", "${JupyterLocalPort}:127.0.0.1:8888", $HostAlias) `
                -WindowStyle Hidden
            Start-Sleep -Seconds 1
            Add-Log "Opened SSH tunnel: http://127.0.0.1:${JupyterLocalPort}/tree"
        } else {
            Add-Log "SSH tunnel already exists: http://127.0.0.1:${JupyterLocalPort}/tree"
        }
        Start-Process "http://127.0.0.1:${JupyterLocalPort}/tree"
    } catch {
        Add-Log "Jupyter launch failed: $($_.Exception.Message)"
    }
}

function Stop-Jupyter {
    try {
        Add-Log "Stopping Jupyter and its Windows SSH tunnel..."
        Get-TunnelProcesses | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        $result = Invoke-KV260Ssh "cd $RemoteProject && ./scripts/kv260-jupyter-notebook.sh --stop"
        Add-Log $result
    } catch {
        Add-Log "Jupyter stop failed: $($_.Exception.Message)"
    }
}

function Read-SudoPassword {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "KV260 sudo password"
    $dialog.StartPosition = "CenterParent"
    $dialog.Size = New-Object System.Drawing.Size(360, 150)
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Enter the KV260 sudo password:"
    $label.Location = New-Object System.Drawing.Point(14, 16)
    $label.Size = New-Object System.Drawing.Size(320, 20)
    $dialog.Controls.Add($label)

    $box = New-Object System.Windows.Forms.TextBox
    $box.Location = New-Object System.Drawing.Point(16, 42)
    $box.Size = New-Object System.Drawing.Size(310, 22)
    $box.UseSystemPasswordChar = $true
    $dialog.Controls.Add($box)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "OK"
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $ok.Location = New-Object System.Drawing.Point(170, 78)
    $dialog.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = "Cancel"
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = New-Object System.Drawing.Point(252, 78)
    $dialog.Controls.Add($cancel)

    $dialog.AcceptButton = $ok
    $dialog.CancelButton = $cancel
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        return $box.Text
    }
    return $null
}

function Invoke-SudoAction {
    param([string]$RemoteCommand, [string]$ActionName)
    if (-not (Confirm-Action "This will $ActionName the KV260. Continue?")) {
        return
    }
    $password = Read-SudoPassword
    if ($null -eq $password) {
        Add-Log "$ActionName cancelled."
        return
    }

    try {
        $ssh = Get-SshExe
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $ssh
        $psi.Arguments = "-o BatchMode=no $HostAlias `"sudo -S -p '' $RemoteCommand`""
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        [void]$process.Start()
        $process.StandardInput.WriteLine($password)
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit(8000) | Out-Null
        Add-Log "$ActionName requested. stdout=$stdout stderr=$stderr"
    } catch {
        Add-Log "$ActionName failed: $($_.Exception.Message)"
    }
}

function Reboot-KV260 {
    Invoke-SudoAction "/sbin/reboot" "reboot"
}

function Shutdown-KV260 {
    Invoke-SudoAction "/sbin/poweroff" "shut down"
}

[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = "KV260 Control Center"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(820, 640)
$form.MinimumSize = New-Object System.Drawing.Size(780, 600)
$form.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 251)

$title = New-Object System.Windows.Forms.Label
$title.Text = "KV260 Control Center"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 21, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
$title.Location = New-Object System.Drawing.Point(24, 18)
$title.Size = New-Object System.Drawing.Size(520, 38)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = "Launch the event camera, board tools, notebooks, and system actions from one Windows entry point."
$subtitle.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
$subtitle.Location = New-Object System.Drawing.Point(26, 58)
$subtitle.Size = New-Object System.Drawing.Size(720, 22)
$form.Controls.Add($subtitle)

function New-Button {
    param(
        [string]$Text,
        [System.Drawing.Color]$BackColor
    )
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Size = New-Object System.Drawing.Size(174, 42)
    $button.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $button.BackColor = $BackColor
    $button.ForeColor = [System.Drawing.Color]::White
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 0
    return $button
}

function Add-ButtonToPanel {
    param(
        [System.Windows.Forms.FlowLayoutPanel]$Panel,
        [string]$Text,
        [System.Drawing.Color]$Color,
        [scriptblock]$Action
    )
    $button = New-Button $Text $Color
    $button.Add_Click($Action)
    $Panel.Controls.Add($button)
}

function New-FlowPanel {
    $panel = New-Object System.Windows.Forms.FlowLayoutPanel
    $panel.Dock = [System.Windows.Forms.DockStyle]::Fill
    $panel.Padding = New-Object System.Windows.Forms.Padding(14)
    $panel.AutoScroll = $true
    $panel.BackColor = [System.Drawing.Color]::White
    return $panel
}

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(24, 92)
$tabs.Size = New-Object System.Drawing.Size(760, 294)
$tabs.Anchor = "Top,Left,Right"
$tabs.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.Controls.Add($tabs)

$cameraTab = New-Object System.Windows.Forms.TabPage
$cameraTab.Text = "Camera"
$cameraPanel = New-FlowPanel
$cameraTab.Controls.Add($cameraPanel)
$tabs.TabPages.Add($cameraTab)

Add-ButtonToPanel $cameraPanel "Open Camera On Windows" ([System.Drawing.Color]::FromArgb(37, 99, 235)) { Start-WindowsX11 }
Add-ButtonToPanel $cameraPanel "Open Camera On KV260" ([System.Drawing.Color]::FromArgb(5, 150, 105)) { Start-BoardDesktop }
Add-ButtonToPanel $cameraPanel "Native Metavision Viewer" ([System.Drawing.Color]::FromArgb(79, 70, 229)) { Open-RemoteApp "native-metavision" "Native Metavision Viewer" }
Add-ButtonToPanel $cameraPanel "Stop Camera Viewers" ([System.Drawing.Color]::FromArgb(220, 38, 38)) { Stop-AllViewers }
Add-ButtonToPanel $cameraPanel "Status" ([System.Drawing.Color]::FromArgb(71, 85, 105)) { Refresh-Status }

$appsTab = New-Object System.Windows.Forms.TabPage
$appsTab.Text = "Applications"
$appsPanel = New-FlowPanel
$appsTab.Controls.Add($appsPanel)
$tabs.TabPages.Add($appsTab)

Add-ButtonToPanel $appsPanel "File Manager" ([System.Drawing.Color]::FromArgb(14, 116, 144)) { Open-RemoteApp "pcmanfm" "File Manager" }
Add-ButtonToPanel $appsPanel "Terminal" ([System.Drawing.Color]::FromArgb(51, 65, 85)) { Open-RemoteApp "terminal" "Terminal" }
Add-ButtonToPanel $appsPanel "RXVT Terminal" ([System.Drawing.Color]::FromArgb(71, 85, 105)) { Open-RemoteApp "terminal-rxvt" "RXVT Terminal" }
Add-ButtonToPanel $appsPanel "Text Editor" ([System.Drawing.Color]::FromArgb(22, 101, 52)) { Open-RemoteApp "editor" "L3afpad Text Editor" }
Add-ButtonToPanel $appsPanel "Appearance" ([System.Drawing.Color]::FromArgb(124, 58, 237)) { Open-RemoteApp "appearance" "Appearance" }
Add-ButtonToPanel $appsPanel "Touch Calibrator" ([System.Drawing.Color]::FromArgb(217, 119, 6)) { Open-RemoteApp "touch-calibrator" "Touch Calibrator" }
Add-ButtonToPanel $appsPanel "Preferred Apps" ([System.Drawing.Color]::FromArgb(8, 145, 178)) { Open-RemoteApp "preferred-apps" "Preferred Applications" }
Add-ButtonToPanel $appsPanel "Desktop Preferences" ([System.Drawing.Color]::FromArgb(67, 56, 202)) { Open-RemoteApp "desktop-preferences" "Desktop Preferences" }

$notebookTab = New-Object System.Windows.Forms.TabPage
$notebookTab.Text = "Notebook And Power"
$notebookPanel = New-FlowPanel
$notebookTab.Controls.Add($notebookPanel)
$tabs.TabPages.Add($notebookTab)

Add-ButtonToPanel $notebookPanel "Open Jupyter Notebook" ([System.Drawing.Color]::FromArgb(234, 88, 12)) { Start-Jupyter }
Add-ButtonToPanel $notebookPanel "Stop Jupyter" ([System.Drawing.Color]::FromArgb(194, 65, 12)) { Stop-Jupyter }
Add-ButtonToPanel $notebookPanel "Reboot KV260" ([System.Drawing.Color]::FromArgb(185, 28, 28)) { Reboot-KV260 }
Add-ButtonToPanel $notebookPanel "Shutdown KV260" ([System.Drawing.Color]::FromArgb(127, 29, 29)) { Shutdown-KV260 }

$script:OutputBox = New-Object System.Windows.Forms.TextBox
$script:OutputBox.Location = New-Object System.Drawing.Point(24, 402)
$script:OutputBox.Size = New-Object System.Drawing.Size(760, 146)
$script:OutputBox.Anchor = "Top,Bottom,Left,Right"
$script:OutputBox.Multiline = $true
$script:OutputBox.ReadOnly = $true
$script:OutputBox.ScrollBars = "Vertical"
$script:OutputBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$script:OutputBox.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
$script:OutputBox.ForeColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
$form.Controls.Add($script:OutputBox)

$footer = New-Object System.Windows.Forms.Label
$footer.Text = "Windows X11 apps use VcXsrv. Camera apps are exclusive because /dev/video0 can have only one owner."
$footer.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$footer.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
$footer.Location = New-Object System.Drawing.Point(24, 562)
$footer.Size = New-Object System.Drawing.Size(760, 20)
$footer.Anchor = "Bottom,Left,Right"
$form.Controls.Add($footer)

$form.Add_Shown({
    Add-Log "Ready. Host alias: $HostAlias"
    Refresh-Status
})

[void]$form.ShowDialog()
