[CmdletBinding()]
param(
    [string]$HostAlias = "petalinux-kv260"
)

$ErrorActionPreference = "Stop"
$InstallDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DesktopDir = [Environment]::GetFolderPath("Desktop")
$ProgramsDir = [Environment]::GetFolderPath("Programs")
$StartMenuDir = Join-Path $ProgramsDir "KV260"
$PowerShellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$IconDll = Join-Path $env:SystemRoot "System32\imageres.dll"

New-Item -ItemType Directory -Force -Path $StartMenuDir | Out-Null

function New-KV260Shortcut {
    param(
        [string]$Path,
        [string]$ScriptName,
        [string]$Description,
        [string]$IconLocation
    )

    $scriptPath = Join-Path $InstallDir $ScriptName
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $shortcut.TargetPath = $PowerShellExe
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -HostAlias `"$HostAlias`""
    $shortcut.WorkingDirectory = $InstallDir
    $shortcut.Description = $Description
    $shortcut.IconLocation = $IconLocation
    $shortcut.Save()
}

$boardShortcutName = "KV260 Event Camera - Board Desktop.lnk"
$x11ShortcutName = "KV260 Event Camera - Windows X11.lnk"

foreach ($folder in @($DesktopDir, $StartMenuDir)) {
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
Write-Host "  $DesktopDir\$boardShortcutName"
Write-Host "  $DesktopDir\$x11ShortcutName"
Write-Host "  $StartMenuDir\$boardShortcutName"
Write-Host "  $StartMenuDir\$x11ShortcutName"
Write-Host ""
Write-Host "For taskbar access, right-click either Start Menu shortcut and choose 'Pin to taskbar'."
