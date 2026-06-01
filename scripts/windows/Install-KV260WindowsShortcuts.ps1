[CmdletBinding()]
param(
    [string]$HostAlias = "petalinux-kv260",
    [switch]$InstallDirectShortcuts
)

$ErrorActionPreference = "Stop"
$InstallDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DesktopDir = [Environment]::GetFolderPath("Desktop")
$ProgramsDir = [Environment]::GetFolderPath("Programs")
$StartMenuDir = Join-Path $ProgramsDir "KV260"
$PowerShellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$IconDll = Join-Path $env:SystemRoot "System32\imageres.dll"
$ControlIcon = Join-Path $InstallDir "kv260-control-center.ico"

New-Item -ItemType Directory -Force -Path $StartMenuDir | Out-Null

function New-KV260ControlIcon {
    param([string]$Path)

    Add-Type -AssemblyName System.Drawing
    $bitmap = New-Object System.Drawing.Bitmap 64, 64
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    $rect = New-Object System.Drawing.Rectangle -ArgumentList 0, 0, 64, 64
    $background = New-Object System.Drawing.Drawing2D.LinearGradientBrush -ArgumentList $rect, ([System.Drawing.Color]::FromArgb(14, 116, 144)), ([System.Drawing.Color]::FromArgb(37, 99, 235)), 45.0
    $graphics.FillRectangle($background, 0, 0, 64, 64)

    $lensBrush = New-Object System.Drawing.SolidBrush -ArgumentList ([System.Drawing.Color]::FromArgb(248, 250, 252))
    $accentBrush = New-Object System.Drawing.SolidBrush -ArgumentList ([System.Drawing.Color]::FromArgb(34, 197, 94))
    $darkBrush = New-Object System.Drawing.SolidBrush -ArgumentList ([System.Drawing.Color]::FromArgb(15, 23, 42))
    $pen = New-Object System.Drawing.Pen -ArgumentList ([System.Drawing.Color]::FromArgb(226, 232, 240)), 3

    $graphics.FillEllipse($lensBrush, 13, 13, 38, 38)
    $graphics.DrawEllipse($pen, 13, 13, 38, 38)
    $graphics.FillEllipse($darkBrush, 23, 23, 18, 18)
    $graphics.FillEllipse($accentBrush, 42, 9, 10, 10)
    $graphics.FillRectangle($accentBrush, 18, 49, 28, 5)

    $font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $graphics.DrawString("KV", $font, $lensBrush, 23, 49)

    $icon = [System.Drawing.Icon]::FromHandle($bitmap.GetHicon())
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create)
    try {
        $icon.Save($stream)
    } finally {
        $stream.Close()
        $graphics.Dispose()
        $bitmap.Dispose()
        $icon.Dispose()
    }
}

function New-KV260Shortcut {
    param(
        [string]$Path,
        [string]$ScriptName,
        [string]$Description,
        [string]$IconLocation,
        [string]$WindowStyle = "Hidden"
    )

    $scriptPath = Join-Path $InstallDir $ScriptName
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $shortcut.TargetPath = $PowerShellExe
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle $WindowStyle -File `"$scriptPath`" -HostAlias `"$HostAlias`""
    $shortcut.WorkingDirectory = $InstallDir
    $shortcut.Description = $Description
    $shortcut.IconLocation = $IconLocation
    $shortcut.Save()
}

$controlShortcutName = "KV260 Control Center.lnk"
$oldControlShortcutName = "KV260 Event Camera.lnk"
$boardShortcutName = "KV260 Event Camera - Board Desktop.lnk"
$x11ShortcutName = "KV260 Event Camera - Windows X11.lnk"
$retiredShortcutNames = @(
    $oldControlShortcutName,
    $boardShortcutName,
    $x11ShortcutName,
    "KV260 Viewer - Open.lnk",
    "KV260 Viewer - Close.lnk",
    "kv260-viewer.lnk"
)

New-KV260ControlIcon -Path $ControlIcon

foreach ($folder in @($DesktopDir, $StartMenuDir)) {
    foreach ($name in @($controlShortcutName) + $retiredShortcutNames) {
        Remove-Item -Force -ErrorAction SilentlyContinue -Path (Join-Path $folder $name)
    }
}

foreach ($folder in @($DesktopDir, $StartMenuDir)) {
    New-KV260Shortcut `
        -Path (Join-Path $folder $controlShortcutName) `
        -ScriptName "Open-KV260EventCamera.ps1" `
        -Description "Open KV260 camera, X11 applications, Jupyter, and board power controls." `
        -IconLocation $ControlIcon `
        -WindowStyle "Normal"

    if ($InstallDirectShortcuts) {
        New-KV260Shortcut `
            -Path (Join-Path $folder $boardShortcutName) `
            -ScriptName "Start-KV260EventCamera-BoardDesktop.ps1" `
            -Description "Open or raise the KV260 Event Camera app on the board HDMI desktop." `
            -IconLocation "$IconDll,102"

        New-KV260Shortcut `
            -Path (Join-Path $folder $x11ShortcutName) `
            -ScriptName "Start-KV260EventCamera-X11.ps1" `
            -Description "Open the KV260 Event Camera app on Windows using SSH X11 forwarding." `
            -IconLocation "$IconDll,100"
    }
}

$sshd = Get-Service -Name sshd -ErrorAction SilentlyContinue
if ($sshd) {
    try {
        Set-Service -Name sshd -StartupType Automatic
        if ($sshd.Status -ne "Running") {
            Start-Service -Name sshd
        }
    } catch {
        Write-Warning "Could not update Windows sshd service startup: $($_.Exception.Message)"
    }
}

Write-Host "Installed KV260 shortcuts:"
Write-Host "  $DesktopDir\$controlShortcutName"
Write-Host "  $StartMenuDir\$controlShortcutName"
if ($InstallDirectShortcuts) {
    Write-Host "  $DesktopDir\$boardShortcutName"
    Write-Host "  $DesktopDir\$x11ShortcutName"
    Write-Host "  $StartMenuDir\$boardShortcutName"
    Write-Host "  $StartMenuDir\$x11ShortcutName"
}
Write-Host ""
Write-Host "For taskbar access, right-click either Start Menu shortcut and choose 'Pin to taskbar'."
