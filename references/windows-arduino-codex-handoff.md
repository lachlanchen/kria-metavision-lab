# Windows Arduino Codex Handoff

Updated: 2026-06-06

This file is written for a separate Codex session running on the Windows machine that has the Arduino connected over USB. It explains what the KV260 board is, how to reach it, and how to use the event-camera recording API that exists on the board.

## Current KV260 Identity

Observed from the KV260 itself on 2026-06-06:

```text
hostname: xilinx-kv260-starterkit-20222
user: petalinux
interface: eth0
IPv4: 192.168.1.250/24
gateway: 192.168.1.1
repo: /home/petalinux/Projects/kria-kv260-starter
github: git@github.com:lachlanchen/kria-metavision-lab.git
```

Use this URL from Windows while the board keeps this DHCP address:

```text
http://192.168.1.250:8765
```

If DHCP changes, get the new address from the board with:

```sh
hostname
ip -4 addr show scope global
```

or from Windows with the existing SSH alias if configured:

```powershell
ssh.exe petalinux-kv260 "hostname; ip -4 addr show scope global"
```

## What This Board Contains

This is an AMD/Xilinx KV260 PetaLinux board configured as a Prophesee event-camera workstation.

Current board-side components:

| Component | Path / Status |
| --- | --- |
| Main repo | `/home/petalinux/Projects/kria-kv260-starter` |
| Event camera node | `/dev/video0` |
| Sensor bias node | `/dev/v4l-subdev3` |
| Recording folder | `/home/petalinux/event_recordings` |
| Custom GTK viewer | `scripts/kv260-event-camera-app.py` |
| Viewer switcher | `scripts/kv260-event-camera-switch.sh` |
| Headless recording API | `scripts/kv260-event-camera-api.py` |
| API wrapper | `scripts/kv260-event-camera-api.sh` |
| Windows experiment client | `scripts/windows/KV260EventExperimentClient.py` |
| API documentation | `references/kv260-remote-recording-api.md` |
| Arduino design documentation | `references/kv260-arduino-cli-control-api.md` |

The event camera recorder writes:

```text
event_YYYYMMDD_HHMMSS.pse2.raw
event_YYYYMMDD_HHMMSS.pse2.raw.json
```

The `.pse2.raw` file is the raw PSE2/EVT2.1 V4L2 payload stream captured from the KV260 camera node. The `.json` sidecar contains metadata and recording stats.

## Current Process State At Handoff

Observed before writing this file:

```text
KV260 Event Camera API: stopped
board desktop viewer: stopped
Windows X11 viewer: stopped
/dev/video0 owners: none
```

Only one process can own `/dev/video0` at a time:

```text
custom GTK viewer
native metavision_viewer
headless recording API
```

The API can stop the GUI/native viewers when `takeover=true`.

## Start The KV260 Recording API

Run on the KV260:

```sh
cd /home/petalinux/Projects/kria-kv260-starter
./scripts/kv260-event-camera-api.sh start
```

Check status on the KV260:

```sh
./scripts/kv260-event-camera-api.sh status
```

Stop it:

```sh
./scripts/kv260-event-camera-api.sh stop
```

Tail logs:

```sh
./scripts/kv260-event-camera-api.sh tail
```

Default API settings:

```text
host: 0.0.0.0
port: 8765
record dir: /home/petalinux/event_recordings
device: /dev/video0
auth: disabled unless KV260_EVENT_API_TOKEN is set
```

## Call The API From Windows

Use this base URL while the board is at `192.168.1.250`:

```powershell
$Board = "http://192.168.1.250:8765"
```

Status:

```powershell
Invoke-RestMethod "$Board/api/v1/status"
```

Start recording:

```powershell
$Body = @{
  prefix = "illumination"
  takeover = $true
  force_takeover = $false
  count_events = $false
  metadata = @{
    source = "windows-arduino-codex"
    trial = "001"
  }
} | ConvertTo-Json -Depth 8

Invoke-RestMethod -Method Post -ContentType "application/json" -Body $Body "$Board/api/v1/record/start"
```

Stop recording:

```powershell
$Stop = @{ close_stream = $true } | ConvertTo-Json
$Result = Invoke-RestMethod -Method Post -ContentType "application/json" -Body $Stop "$Board/api/v1/record/stop"
$Result.stopped_recording.path
$Result.stopped_recording.meta_path
```

Download raw and JSON:

```powershell
$RawPath = $Result.stopped_recording.path
$JsonPath = $Result.stopped_recording.meta_path
$Out = "$env:USERPROFILE\Downloads\kv260-events"
New-Item -ItemType Directory -Force -Path $Out | Out-Null

$RawUrl = "$Board/api/v1/recordings/download?path=$([uri]::EscapeDataString($RawPath))"
$JsonUrl = "$Board/api/v1/recordings/download?path=$([uri]::EscapeDataString($JsonPath))"

Invoke-WebRequest $RawUrl -OutFile (Join-Path $Out (Split-Path $RawPath -Leaf))
Invoke-WebRequest $JsonUrl -OutFile (Join-Path $Out (Split-Path $JsonPath -Leaf))
```

List recent recordings:

```powershell
Invoke-RestMethod "$Board/api/v1/recordings?limit=20"
```

## Use The Existing Windows Python Client

Client script in this repo:

```text
scripts/windows/KV260EventExperimentClient.py
```

From Windows, use the current board URL explicitly:

```powershell
python .\KV260EventExperimentClient.py --board-url http://192.168.1.250:8765 status
```

Run an Arduino-light experiment where event recording starts before the light changes:

```powershell
python .\KV260EventExperimentClient.py `
  --board-url http://192.168.1.250:8765 `
  run `
  --arduino-port COM3 `
  --arduino-baud 115200 `
  --light-on "ON" `
  --light-off "OFF" `
  --seconds 5 `
  --prefix illumination `
  --metadata trial=001 `
  --output-dir "$env:USERPROFILE\Downloads\kv260-events"
```

The default experiment mode is:

```text
record-then-light
```

That is the safer default for event cameras because it captures the fast illumination transition.

## Windows Arduino Codex Responsibilities

The Windows Arduino Codex session should own these tasks:

1. Detect and control the Arduino connected to Windows USB.
2. Install or find `arduino-cli` on Windows.
3. Use `arduino-cli` for board discovery, core install, library install, sketch compile, sketch upload, and optional bootloader burn.
4. Use direct serial I/O for runtime light commands.
5. Call the KV260 recording API before/during/after light stimulation.
6. Download event recordings from the KV260 after each run.
7. Keep a local Windows log of commands, serial responses, KV260 API responses, and downloaded file paths.

Do not try to run Arduino CLI on the KV260 unless the Arduino is physically connected to the KV260 USB port.

## Recommended Windows Arduino Architecture

Use two layers:

| Layer | Purpose |
| --- | --- |
| Arduino CLI wrapper | Compile/upload/burn operations |
| Serial control API | Real-time light commands |

Recommended local Windows API:

```text
http://127.0.0.1:8780
```

Recommended endpoints:

```text
GET  /api/v1/arduino/status
GET  /api/v1/arduino/boards
POST /api/v1/arduino/core/install
POST /api/v1/arduino/library/install
POST /api/v1/arduino/sketch/compile
POST /api/v1/arduino/sketch/upload
POST /api/v1/arduino/sketch/compile-upload
POST /api/v1/arduino/serial/connect
POST /api/v1/arduino/serial/command
POST /api/v1/light/on
POST /api/v1/light/off
POST /api/v1/light/pwm
POST /api/v1/experiment/run
```

See the full design:

```text
references/kv260-arduino-cli-control-api.md
```

## Arduino CLI Command Patterns

Check CLI:

```powershell
arduino-cli version --json
```

Initialize and update:

```powershell
arduino-cli config init
arduino-cli core update-index
```

Detect board:

```powershell
arduino-cli board list --json
```

Install Uno core:

```powershell
arduino-cli core install arduino:avr
```

Compile:

```powershell
arduino-cli compile --fqbn arduino:avr:uno C:\path\to\LightController
```

Upload:

```powershell
arduino-cli upload -p COM3 --fqbn arduino:avr:uno C:\path\to\LightController
```

Bootloader burn is advanced and should require explicit confirmation:

```powershell
arduino-cli burn-bootloader -b arduino:avr:uno -P atmel_ice
```

Do not expose bootloader burn as a normal upload button.

## Suggested Arduino Serial Protocol

Use a simple line-based protocol:

```text
PING
ON
OFF
PWM 0..255
PULSE <on_ms> <off_ms> <count>
STATUS
```

Expected responses:

```text
OK <command>
ERR <reason>
STATE light=<0|1> pwm=<0..255>
```

The existing Windows Python experiment client already supports sending `--light-on` and `--light-off` commands to a serial port when `pyserial` is installed.

## Pasteable Prompt For Windows Arduino Codex

Use this as the first message for the Windows Arduino Codex session:

```text
You are on the Windows host that has an Arduino connected over USB for light illumination. A KV260 PetaLinux board exists on the LAN:

- hostname: xilinx-kv260-starterkit-20222
- current IP: 192.168.1.250
- KV260 repo: /home/petalinux/Projects/kria-kv260-starter
- KV260 GitHub repo: lachlanchen/kria-metavision-lab
- KV260 event camera node: /dev/video0
- KV260 recording API port: 8765
- KV260 API URL: http://192.168.1.250:8765

The KV260 has a headless event recording API:
- start on board: cd /home/petalinux/Projects/kria-kv260-starter && ./scripts/kv260-event-camera-api.sh start
- status: GET http://192.168.1.250:8765/api/v1/status
- start recording: POST /api/v1/record/start
- stop recording: POST /api/v1/record/stop
- download recording: GET /api/v1/recordings/download?path=<path>

The KV260 records .pse2.raw plus .json sidecar files in /home/petalinux/event_recordings. Only one process can own /dev/video0; use takeover=true when starting API recording.

Your Windows-side task is to build the Arduino CLI/control layer:
- use arduino-cli for board list, core install, library install, compile, upload, and advanced bootloader burn
- use direct serial I/O for runtime light commands ON/OFF/PWM/PULSE
- provide a Windows GUI/API that can trigger the Arduino light and call the KV260 API to start/stop/download event recordings
- use board URL http://192.168.1.250:8765 unless DHCP changes

Reference docs in the repo:
- references/kv260-remote-recording-api.md
- references/kv260-arduino-cli-control-api.md
- references/windows-arduino-codex-handoff.md
```

## Source References

Local repo docs:

```text
references/kv260-remote-recording-api.md
references/kv260-arduino-cli-control-api.md
references/kv260-event-camera-app.md
```

Official Arduino CLI docs:

```text
https://docs.arduino.cc/arduino-cli/installation/
https://docs.arduino.cc/arduino-cli/getting-started/
https://docs.arduino.cc/arduino-cli/commands-reference/arduino-cli_board_list/
https://docs.arduino.cc/arduino-cli/commands-reference/arduino-cli_compile/
https://docs.arduino.cc/arduino-cli/commands-reference/arduino-cli_upload/
https://docs.arduino.cc/arduino-cli/commands-reference/arduino-cli_burn-bootloader/
```
