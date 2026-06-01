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

function Get-ScpExe {
    return (Get-Command scp.exe -ErrorAction Stop).Source
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
    Write-Host "SCP=$(Get-ScpExe)"
    Write-Host "BOARD_SCRIPT=$BoardScript"
    Write-Host "X11_SCRIPT=$X11Script"
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

function Add-Log {
    param([string]$Text)
    $timestamp = Get-Date -Format "HH:mm:ss"
    $script:OutputBox.AppendText("[$timestamp] $Text`r`n")
}

function Format-FileSize {
    param([object]$Length)
    if ($null -eq $Length) {
        return ""
    }
    $size = [double]$Length
    $units = @("B", "KB", "MB", "GB", "TB")
    $index = 0
    while ($size -ge 1024 -and $index -lt ($units.Count - 1)) {
        $size = $size / 1024
        $index++
    }
    if ($index -eq 0) {
        return "{0:N0} B" -f $size
    }
    return "{0:N1} {1}" -f $size, $units[$index]
}

function ConvertTo-RemoteShellLiteral {
    param([string]$Value)
    return "'" + $Value.Replace("'", "'\''") + "'"
}

function ConvertTo-ScpRemoteSpec {
    param([string]$RemotePath)
    return "${HostAlias}:$(ConvertTo-RemoteShellLiteral $RemotePath)"
}

function Invoke-ScpCopy {
    param([string[]]$Arguments)
    $scp = Get-ScpExe
    Add-Log "scp $($Arguments -join ' ')"
    $output = & $scp @Arguments 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        throw "scp exited with code $code`r`n$($output -join "`r`n")"
    }
    if ($output) {
        Add-Log ($output -join "`r`n")
    }
}

function Invoke-FileAction {
    param([scriptblock]$Action)
    try {
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        [System.Windows.Forms.Application]::DoEvents()
        & $Action
    } catch {
        Add-Log "Files: $($_.Exception.Message)"
        Show-Message $_.Exception.Message "KV260 File Transfer"
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}

function New-FileListView {
    $list = New-Object System.Windows.Forms.ListView
    $list.View = [System.Windows.Forms.View]::Details
    $list.FullRowSelect = $true
    $list.MultiSelect = $true
    $list.HideSelection = $false
    $list.AllowDrop = $true
    $list.Anchor = "Top,Bottom,Left,Right"
    [void]$list.Columns.Add("Name", 250)
    [void]$list.Columns.Add("Type", 72)
    [void]$list.Columns.Add("Size", 82)
    [void]$list.Columns.Add("Modified", 132)
    return $list
}

function Add-FileListRow {
    param(
        [System.Windows.Forms.ListView]$List,
        [string]$Name,
        [bool]$IsDirectory,
        [object]$Size,
        [object]$Modified,
        [string]$Path
    )
    $item = New-Object System.Windows.Forms.ListViewItem($Name)
    [void]$item.SubItems.Add($(if ($IsDirectory) { "Folder" } else { "File" }))
    [void]$item.SubItems.Add($(if ($IsDirectory) { "" } else { Format-FileSize $Size }))
    $modifiedText = ""
    if ($Modified) {
        try {
            $modifiedText = ([DateTime]$Modified).ToString("yyyy-MM-dd HH:mm")
        } catch {
            $modifiedText = [string]$Modified
        }
    }
    [void]$item.SubItems.Add($modifiedText)
    $item.Tag = [pscustomobject]@{
        Path = $Path
        IsDirectory = $IsDirectory
    }
    [void]$List.Items.Add($item)
}

function Get-SelectedFileTags {
    param([System.Windows.Forms.ListView]$List)
    $tags = @()
    foreach ($item in $List.SelectedItems) {
        $tags += $item.Tag
    }
    return $tags
}

function Refresh-LocalFiles {
    Invoke-FileAction {
        $path = $script:LocalPathText.Text.Trim()
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Local path does not exist: $path"
        }
        $resolved = (Resolve-Path -LiteralPath $path).Path
        $script:LocalPathText.Text = $resolved
        $script:LocalList.Items.Clear()
        Get-ChildItem -Force -LiteralPath $resolved |
            Sort-Object -Property @{ Expression = { $_.PSIsContainer }; Descending = $true }, Name |
            ForEach-Object {
                Add-FileListRow `
                    -List $script:LocalList `
                    -Name $_.Name `
                    -IsDirectory $_.PSIsContainer `
                    -Size $_.Length `
                    -Modified $_.LastWriteTime `
                    -Path $_.FullName
            }
        Add-Log "Local refreshed: $resolved"
    }
}

function Get-KV260Directory {
    param([string]$Path)
    $python = @"
import json, os, sys
p = os.path.abspath(sys.argv[1])
items = []
for name in sorted(os.listdir(p), key=lambda n: (not os.path.isdir(os.path.join(p, n)), n.lower())):
    q = os.path.join(p, name)
    try:
        s = os.lstat(q)
    except OSError:
        continue
    items.append({
        "name": name,
        "path": q,
        "is_dir": os.path.isdir(q),
        "size": s.st_size,
        "mtime": s.st_mtime,
    })
print(json.dumps({"path": p, "parent": os.path.dirname(p), "items": items}))
"@
    $command = "python3 -c $(ConvertTo-RemoteShellLiteral $python) $(ConvertTo-RemoteShellLiteral $Path)"
    $json = Invoke-KV260Ssh $command
    return ($json | ConvertFrom-Json)
}

function Refresh-RemoteFiles {
    Invoke-FileAction {
        $path = $script:RemotePathText.Text.Trim()
        $data = Get-KV260Directory $path
        $script:RemotePathText.Text = $data.path
        $script:RemoteList.Items.Clear()
        foreach ($entry in @($data.items)) {
            $modified = $null
            if ($entry.mtime) {
                $modified = ([DateTimeOffset]::FromUnixTimeSeconds([int64]$entry.mtime)).LocalDateTime
            }
            Add-FileListRow `
                -List $script:RemoteList `
                -Name $entry.name `
                -IsDirectory ([bool]$entry.is_dir) `
                -Size $entry.size `
                -Modified $modified `
                -Path $entry.path
        }
        Add-Log "KV260 refreshed: $($data.path)"
    }
}

function Refresh-FileBrowsers {
    Refresh-LocalFiles
    Refresh-RemoteFiles
}

function Set-LocalParent {
    $path = $script:LocalPathText.Text.Trim()
    $parent = Split-Path -Parent $path
    if ($parent) {
        $script:LocalPathText.Text = $parent
        Refresh-LocalFiles
    }
}

function Set-RemoteParent {
    $path = $script:RemotePathText.Text.Trim().TrimEnd("/")
    $parent = Split-Path -Parent $path
    if ($parent) {
        $script:RemotePathText.Text = $parent.Replace("\", "/")
        Refresh-RemoteFiles
    }
}

function Upload-LocalPaths {
    param([string[]]$Paths)
    if (-not $Paths -or $Paths.Count -eq 0) {
        Add-Log "Upload skipped: no local files selected."
        return
    }
    Invoke-FileAction {
        $remoteDir = $script:RemotePathText.Text.Trim()
        $dest = (ConvertTo-ScpRemoteSpec $remoteDir) + "/"
        foreach ($path in $Paths) {
            Invoke-ScpCopy -Arguments @("-O", "-r", $path, $dest)
        }
        Add-Log "Uploaded $($Paths.Count) item(s) to $remoteDir"
        Refresh-RemoteFiles
    }
}

function Download-RemotePaths {
    param([string[]]$Paths)
    if (-not $Paths -or $Paths.Count -eq 0) {
        Add-Log "Download skipped: no KV260 files selected."
        return
    }
    Invoke-FileAction {
        $localDir = $script:LocalPathText.Text.Trim()
        foreach ($path in $Paths) {
            Invoke-ScpCopy -Arguments @("-O", "-r", (ConvertTo-ScpRemoteSpec $path), $localDir)
        }
        Add-Log "Downloaded $($Paths.Count) item(s) to $localDir"
        Refresh-LocalFiles
    }
}

function Upload-SelectedFiles {
    $paths = @(Get-SelectedFileTags $script:LocalList | ForEach-Object { $_.Path })
    Upload-LocalPaths $paths
}

function Download-SelectedFiles {
    $paths = @(Get-SelectedFileTags $script:RemoteList | ForEach-Object { $_.Path })
    Download-RemotePaths $paths
}

function Browse-LocalFolder {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.SelectedPath = $script:LocalPathText.Text
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:LocalPathText.Text = $dialog.SelectedPath
        Refresh-LocalFiles
    }
}

function New-RemoteFolder {
    $name = [Microsoft.VisualBasic.Interaction]::InputBox("Folder name:", "New KV260 Folder", "new-folder")
    if ([string]::IsNullOrWhiteSpace($name)) {
        return
    }
    Invoke-FileAction {
        $base = $script:RemotePathText.Text.Trim().TrimEnd("/")
        $target = "$base/$name"
        Invoke-KV260Ssh "mkdir -p $(ConvertTo-RemoteShellLiteral $target)" | Out-Null
        Add-Log "Created remote folder: $target"
        Refresh-RemoteFiles
    }
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
$form.Size = New-Object System.Drawing.Size(1040, 760)
$form.MinimumSize = New-Object System.Drawing.Size(960, 680)
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
$subtitle.Size = New-Object System.Drawing.Size(940, 22)
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
$tabs.Size = New-Object System.Drawing.Size(980, 416)
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
Add-ButtonToPanel $appsPanel "File Transfer GUI" ([System.Drawing.Color]::FromArgb(37, 99, 235)) { Open-RemoteApp "file-transfer" "KV260 File Transfer" }

$filesTab = New-Object System.Windows.Forms.TabPage
$filesTab.Text = "Files"
$tabs.TabPages.Add($filesTab)

$filesHeader = New-Object System.Windows.Forms.Label
$filesHeader.Text = "Copy files and folders between Windows and the KV260. Multi-select rows, use the buttons, or drag between panes."
$filesHeader.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$filesHeader.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
$filesHeader.Location = New-Object System.Drawing.Point(14, 12)
$filesHeader.Size = New-Object System.Drawing.Size(920, 22)
$filesHeader.Anchor = "Top,Left,Right"
$filesTab.Controls.Add($filesHeader)

$localLabel = New-Object System.Windows.Forms.Label
$localLabel.Text = "Windows"
$localLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$localLabel.Location = New-Object System.Drawing.Point(14, 42)
$localLabel.Size = New-Object System.Drawing.Size(120, 22)
$filesTab.Controls.Add($localLabel)

$remoteLabel = New-Object System.Windows.Forms.Label
$remoteLabel.Text = "KV260"
$remoteLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$remoteLabel.Location = New-Object System.Drawing.Point(500, 42)
$remoteLabel.Size = New-Object System.Drawing.Size(120, 22)
$filesTab.Controls.Add($remoteLabel)

$script:LocalPathText = New-Object System.Windows.Forms.TextBox
$script:LocalPathText.Text = [Environment]::GetFolderPath("MyDocuments")
$script:LocalPathText.Location = New-Object System.Drawing.Point(14, 68)
$script:LocalPathText.Size = New-Object System.Drawing.Size(354, 24)
$script:LocalPathText.Anchor = "Top,Left"
$script:LocalPathText.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        Refresh-LocalFiles
        $_.SuppressKeyPress = $true
    }
})
$filesTab.Controls.Add($script:LocalPathText)

$localBrowse = New-Button "Browse" ([System.Drawing.Color]::FromArgb(14, 116, 144))
$localBrowse.Size = New-Object System.Drawing.Size(84, 28)
$localBrowse.Location = New-Object System.Drawing.Point(374, 66)
$localBrowse.Add_Click({ Browse-LocalFolder })
$filesTab.Controls.Add($localBrowse)

$localUp = New-Button "Up" ([System.Drawing.Color]::FromArgb(71, 85, 105))
$localUp.Size = New-Object System.Drawing.Size(48, 28)
$localUp.Location = New-Object System.Drawing.Point(464, 66)
$localUp.Add_Click({ Set-LocalParent })
$filesTab.Controls.Add($localUp)

$script:RemotePathText = New-Object System.Windows.Forms.TextBox
$script:RemotePathText.Text = $RemoteProject
$script:RemotePathText.Location = New-Object System.Drawing.Point(500, 68)
$script:RemotePathText.Size = New-Object System.Drawing.Size(344, 24)
$script:RemotePathText.Anchor = "Top,Left,Right"
$script:RemotePathText.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        Refresh-RemoteFiles
        $_.SuppressKeyPress = $true
    }
})
$filesTab.Controls.Add($script:RemotePathText)

$remoteRefresh = New-Button "Refresh" ([System.Drawing.Color]::FromArgb(71, 85, 105))
$remoteRefresh.Size = New-Object System.Drawing.Size(82, 28)
$remoteRefresh.Location = New-Object System.Drawing.Point(850, 66)
$remoteRefresh.Anchor = "Top,Right"
$remoteRefresh.Add_Click({ Refresh-RemoteFiles })
$filesTab.Controls.Add($remoteRefresh)

$remoteUp = New-Button "Up" ([System.Drawing.Color]::FromArgb(71, 85, 105))
$remoteUp.Size = New-Object System.Drawing.Size(48, 28)
$remoteUp.Location = New-Object System.Drawing.Point(938, 66)
$remoteUp.Anchor = "Top,Right"
$remoteUp.Add_Click({ Set-RemoteParent })
$filesTab.Controls.Add($remoteUp)

$script:LocalList = New-FileListView
$script:LocalList.Location = New-Object System.Drawing.Point(14, 102)
$script:LocalList.Size = New-Object System.Drawing.Size(472, 220)
$script:LocalList.Add_DoubleClick({
    if ($script:LocalList.SelectedItems.Count -eq 1) {
        $tag = $script:LocalList.SelectedItems[0].Tag
        if ($tag.IsDirectory) {
            $script:LocalPathText.Text = $tag.Path
            Refresh-LocalFiles
        }
    }
})
$script:LocalList.Add_ItemDrag({
    $paths = @(Get-SelectedFileTags $script:LocalList | ForEach-Object { $_.Path })
    if ($paths.Count -gt 0) {
        $data = New-Object System.Windows.Forms.DataObject
        $data.SetData("KV260LocalPaths", ($paths -join "`n"))
        [void]$script:LocalList.DoDragDrop($data, [System.Windows.Forms.DragDropEffects]::Copy)
    }
})
$script:LocalList.Add_DragEnter({
    if ($_.Data.GetDataPresent("KV260RemotePaths")) {
        $_.Effect = [System.Windows.Forms.DragDropEffects]::Copy
    }
})
$script:LocalList.Add_DragDrop({
    if ($_.Data.GetDataPresent("KV260RemotePaths")) {
        $paths = ([string]$_.Data.GetData("KV260RemotePaths")) -split "`n" | Where-Object { $_ }
        Download-RemotePaths $paths
    }
})
$filesTab.Controls.Add($script:LocalList)

$script:RemoteList = New-FileListView
$script:RemoteList.Location = New-Object System.Drawing.Point(500, 102)
$script:RemoteList.Size = New-Object System.Drawing.Size(486, 220)
$script:RemoteList.Anchor = "Top,Bottom,Left,Right"
$script:RemoteList.Add_DoubleClick({
    if ($script:RemoteList.SelectedItems.Count -eq 1) {
        $tag = $script:RemoteList.SelectedItems[0].Tag
        if ($tag.IsDirectory) {
            $script:RemotePathText.Text = $tag.Path
            Refresh-RemoteFiles
        }
    }
})
$script:RemoteList.Add_ItemDrag({
    $paths = @(Get-SelectedFileTags $script:RemoteList | ForEach-Object { $_.Path })
    if ($paths.Count -gt 0) {
        $data = New-Object System.Windows.Forms.DataObject
        $data.SetData("KV260RemotePaths", ($paths -join "`n"))
        [void]$script:RemoteList.DoDragDrop($data, [System.Windows.Forms.DragDropEffects]::Copy)
    }
})
$script:RemoteList.Add_DragEnter({
    if ($_.Data.GetDataPresent("KV260LocalPaths") -or $_.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
        $_.Effect = [System.Windows.Forms.DragDropEffects]::Copy
    }
})
$script:RemoteList.Add_DragDrop({
    if ($_.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
        $paths = [string[]]$_.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
        Upload-LocalPaths $paths
    } elseif ($_.Data.GetDataPresent("KV260LocalPaths")) {
        $paths = ([string]$_.Data.GetData("KV260LocalPaths")) -split "`n" | Where-Object { $_ }
        Upload-LocalPaths $paths
    }
})
$filesTab.Controls.Add($script:RemoteList)

$uploadButton = New-Button "Upload Selected ->" ([System.Drawing.Color]::FromArgb(5, 150, 105))
$uploadButton.Location = New-Object System.Drawing.Point(14, 334)
$uploadButton.Size = New-Object System.Drawing.Size(154, 34)
$uploadButton.Add_Click({ Upload-SelectedFiles })
$filesTab.Controls.Add($uploadButton)

$downloadButton = New-Button "<- Download Selected" ([System.Drawing.Color]::FromArgb(37, 99, 235))
$downloadButton.Location = New-Object System.Drawing.Point(174, 334)
$downloadButton.Size = New-Object System.Drawing.Size(166, 34)
$downloadButton.Add_Click({ Download-SelectedFiles })
$filesTab.Controls.Add($downloadButton)

$refreshFilesButton = New-Button "Refresh Both" ([System.Drawing.Color]::FromArgb(71, 85, 105))
$refreshFilesButton.Location = New-Object System.Drawing.Point(346, 334)
$refreshFilesButton.Size = New-Object System.Drawing.Size(116, 34)
$refreshFilesButton.Add_Click({ Refresh-FileBrowsers })
$filesTab.Controls.Add($refreshFilesButton)

$newRemoteFolder = New-Button "New KV260 Folder" ([System.Drawing.Color]::FromArgb(217, 119, 6))
$newRemoteFolder.Location = New-Object System.Drawing.Point(500, 334)
$newRemoteFolder.Size = New-Object System.Drawing.Size(146, 34)
$newRemoteFolder.Add_Click({ New-RemoteFolder })
$filesTab.Controls.Add($newRemoteFolder)

$openBoardTransfer = New-Button "Open Board Transfer GUI" ([System.Drawing.Color]::FromArgb(79, 70, 229))
$openBoardTransfer.Location = New-Object System.Drawing.Point(652, 334)
$openBoardTransfer.Size = New-Object System.Drawing.Size(176, 34)
$openBoardTransfer.Add_Click({ Open-RemoteApp "file-transfer" "KV260 File Transfer" })
$filesTab.Controls.Add($openBoardTransfer)

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
$script:OutputBox.Location = New-Object System.Drawing.Point(24, 524)
$script:OutputBox.Size = New-Object System.Drawing.Size(980, 126)
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
$footer.Location = New-Object System.Drawing.Point(24, 666)
$footer.Size = New-Object System.Drawing.Size(980, 20)
$footer.Anchor = "Bottom,Left,Right"
$form.Controls.Add($footer)

$form.Add_Shown({
    Add-Log "Ready. Host alias: $HostAlias"
    Refresh-Status
    Refresh-LocalFiles
    Refresh-RemoteFiles
})

[void]$form.ShowDialog()
