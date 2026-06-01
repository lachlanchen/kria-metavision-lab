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
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

if ($CheckOnly) {
    $missing = @($BoardScript, $X11Script) | Where-Object { -not (Test-Path $_) }
    if ($missing) {
        Write-Host "MISSING=$($missing -join ',')"
        exit 1
    }
    $ssh = (Get-Command ssh.exe -ErrorAction Stop).Source
    Write-Host "SSH=$ssh"
    Write-Host "BOARD_SCRIPT=$BoardScript"
    Write-Host "X11_SCRIPT=$X11Script"
    & $ssh -o BatchMode=yes $HostAlias "cd $RemoteProject && ./scripts/kv260-event-camera-switch.sh --status"
    exit $LASTEXITCODE
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Invoke-KV260Ssh {
    param([string]$RemoteCommand)
    $ssh = (Get-Command ssh.exe -ErrorAction Stop).Source
    $output = & $ssh -o BatchMode=yes $HostAlias $RemoteCommand 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        throw "ssh exited with code $code`r`n$output"
    }
    return ($output -join "`r`n")
}

function Add-Log {
    param([string]$Text)
    $timestamp = Get-Date -Format "HH:mm:ss"
    $script:OutputBox.AppendText("[$timestamp] $Text`r`n")
}

function Refresh-Status {
    try {
        $status = Invoke-KV260Ssh "cd $RemoteProject && ./scripts/kv260-event-camera-switch.sh --status"
        $vcxsrv = if (Get-Process -Name vcxsrv -ErrorAction SilentlyContinue) { "running" } else { "not running" }
        Add-Log "Status:`r`n$status`r`nVcXsrv: $vcxsrv"
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
        Add-Log "Stopping all custom KV260 event camera viewers..."
        $result = Invoke-KV260Ssh "cd $RemoteProject && ./scripts/kv260-event-camera-switch.sh --stop-all && ./scripts/kv260-event-camera-switch.sh --status"
        Add-Log $result
    } catch {
        Add-Log "Stop failed: $($_.Exception.Message)"
    }
}

[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = "KV260 Event Camera"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(620, 430)
$form.MinimumSize = New-Object System.Drawing.Size(560, 380)
$form.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 252)

$title = New-Object System.Windows.Forms.Label
$title.Text = "KV260 Event Camera"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::FromArgb(17, 24, 39)
$title.Location = New-Object System.Drawing.Point(22, 18)
$title.Size = New-Object System.Drawing.Size(560, 34)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = "Choose where the live event-camera GUI should run. Starting one mode stops the other."
$subtitle.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(75, 85, 99)
$subtitle.Location = New-Object System.Drawing.Point(24, 56)
$subtitle.Size = New-Object System.Drawing.Size(560, 22)
$form.Controls.Add($subtitle)

function New-Button {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [System.Drawing.Color]$BackColor
    )
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size(176, 44)
    $button.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $button.BackColor = $BackColor
    $button.ForeColor = [System.Drawing.Color]::White
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 0
    return $button
}

$windowsButton = New-Button "Open On Windows" 24 96 ([System.Drawing.Color]::FromArgb(37, 99, 235))
$boardButton = New-Button "Open On KV260 Display" 212 96 ([System.Drawing.Color]::FromArgb(5, 150, 105))
$stopButton = New-Button "Stop All Viewers" 400 96 ([System.Drawing.Color]::FromArgb(220, 38, 38))
$statusButton = New-Button "Status" 24 150 ([System.Drawing.Color]::FromArgb(55, 65, 81))
$closeButton = New-Button "Close Panel" 212 150 ([System.Drawing.Color]::FromArgb(107, 114, 128))

$windowsButton.Add_Click({ Start-WindowsX11 })
$boardButton.Add_Click({ Start-BoardDesktop })
$stopButton.Add_Click({ Stop-AllViewers })
$statusButton.Add_Click({ Refresh-Status })
$closeButton.Add_Click({ $form.Close() })

$form.Controls.Add($windowsButton)
$form.Controls.Add($boardButton)
$form.Controls.Add($stopButton)
$form.Controls.Add($statusButton)
$form.Controls.Add($closeButton)

$script:OutputBox = New-Object System.Windows.Forms.TextBox
$script:OutputBox.Location = New-Object System.Drawing.Point(24, 214)
$script:OutputBox.Size = New-Object System.Drawing.Size(556, 142)
$script:OutputBox.Anchor = "Top,Bottom,Left,Right"
$script:OutputBox.Multiline = $true
$script:OutputBox.ReadOnly = $true
$script:OutputBox.ScrollBars = "Vertical"
$script:OutputBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$script:OutputBox.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
$script:OutputBox.ForeColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
$form.Controls.Add($script:OutputBox)

$footer = New-Object System.Windows.Forms.Label
$footer.Text = "The camera can stream in only one place at a time because /dev/video0 is exclusive."
$footer.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$footer.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
$footer.Location = New-Object System.Drawing.Point(24, 364)
$footer.Size = New-Object System.Drawing.Size(556, 20)
$footer.Anchor = "Bottom,Left,Right"
$form.Controls.Add($footer)

$form.Add_Shown({
    Add-Log "Ready. Host alias: $HostAlias"
    Refresh-Status
})

[void]$form.ShowDialog()
