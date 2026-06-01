[CmdletBinding()]
param(
    [string]$HostAlias = "petalinux-kv260",
    [string]$RemoteProject = "/home/petalinux/Projects/kria-kv260-starter",
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"
$LogDir = Join-Path $env:TEMP "kv260-event-camera"
$LogFile = Join-Path $LogDir "board-desktop-launch.log"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Show-KV260Message {
    param([string]$Text)
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shell.Popup($Text, 8, "KV260 Event Camera", 48) | Out-Null
    } catch {
        Write-Host $Text
    }
}

$ssh = (Get-Command ssh.exe -ErrorAction Stop).Source
$remoteCommand = "cd $RemoteProject && DISPLAY=:0 XAUTHORITY=/home/petalinux/.Xauthority ./scripts/kv260-event-camera-app.sh"

if ($CheckOnly) {
    & $ssh -o BatchMode=yes $HostAlias "echo kv260-board-ok"
    exit $LASTEXITCODE
}

try {
    "[$(Get-Date -Format s)] ssh $HostAlias $remoteCommand" | Out-File -FilePath $LogFile -Append -Encoding utf8
    & $ssh -o BatchMode=yes $HostAlias $remoteCommand 2>&1 | Out-File -FilePath $LogFile -Append -Encoding utf8
    if ($LASTEXITCODE -ne 0) {
        throw "ssh exited with code $LASTEXITCODE"
    }
} catch {
    "[$(Get-Date -Format s)] ERROR $($_.Exception.Message)" | Out-File -FilePath $LogFile -Append -Encoding utf8
    Show-KV260Message "Could not open the KV260 board desktop viewer. Check $LogFile"
    exit 1
}
