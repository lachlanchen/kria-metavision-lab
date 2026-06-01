[CmdletBinding()]
param(
    [string]$HostAlias = "petalinux-kv260",
    [string]$RemoteProject = "/home/petalinux/Projects/kria-kv260-starter",
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"
$LogDir = Join-Path $env:TEMP "kv260-event-camera"
$LogFile = Join-Path $LogDir "windows-x11-launch.log"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Show-KV260Message {
    param([string]$Text)
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shell.Popup($Text, 10, "KV260 Event Camera", 48) | Out-Null
    } catch {
        Write-Host $Text
    }
}

function Find-VcXsrv {
    $programFilesX86 = [Environment]::GetFolderPath("ProgramFilesX86")
    $candidates = @(
        (Join-Path $env:ProgramFiles "VcXsrv\vcxsrv.exe"),
        (Join-Path $programFilesX86 "VcXsrv\vcxsrv.exe")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }
    return $null
}

try {
    $vcxsrv = Find-VcXsrv
    $ssh = (Get-Command ssh.exe -ErrorAction Stop).Source
    $remoteCommand = "cd $RemoteProject && ./scripts/kv260-event-camera-x11.sh"

    if ($CheckOnly) {
        if ($vcxsrv) {
            Write-Host "VCXSRV=$vcxsrv"
        } else {
            Write-Host "VCXSRV_MISSING"
        }
        Write-Host "SSH=$ssh"
        Write-Host "REMOTE=$remoteCommand"
        exit 0
    }

    if (-not $vcxsrv) {
        Show-KV260Message "VcXsrv is not installed. Install VcXsrv, then run this shortcut again."
        exit 2
    }

    if (-not (Get-Process -Name vcxsrv -ErrorAction SilentlyContinue)) {
        Start-Process -FilePath $vcxsrv -ArgumentList @(":0", "-multiwindow", "-clipboard", "-wgl", "-ac")
        Start-Sleep -Seconds 2
    }

    $env:DISPLAY = "localhost:0.0"
    "[$(Get-Date -Format s)] starting ssh -Y $HostAlias $remoteCommand" | Out-File -FilePath $LogFile -Append -Encoding utf8

    Start-Process `
        -FilePath $ssh `
        -ArgumentList @("-Y", "-o", "ForwardX11Trusted=yes", "-o", "BatchMode=yes", $HostAlias, $remoteCommand) `
        -WindowStyle Minimized
} catch {
    "[$(Get-Date -Format s)] ERROR $($_.Exception.Message)" | Out-File -FilePath $LogFile -Append -Encoding utf8
    Show-KV260Message "Could not open the KV260 X11 viewer. Check $LogFile"
    exit 1
}
