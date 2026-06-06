# KV260 Remote Recording API

Updated: 2026-06-06

This note documents the headless recording API for Windows-controlled experiments. The common use case is:

```text
Windows controls Arduino light source -> Windows calls KV260 API -> KV260 records event stream -> Windows downloads .pse2.raw + .json
```

## Design Decision

Use two paths:

| Path | Purpose |
| --- | --- |
| Custom GTK GUI | Human preview, manual record, playback, bias/display checks |
| Headless HTTP API | Experiment automation, start/stop/download from Windows or another host |

The API does not automate mouse clicks or depend on X11. It reuses the same direct V4L2 raw writer as the GUI, but disables preview and event decoding by default. This keeps recording focused on:

```text
DQBUF -> copy payload -> QBUF -> enqueue raw payload -> writer thread -> disk
```

Only one process can own `/dev/video0`. When starting a remote recording, the API can ask the existing GUI/native viewers to stop first.

## Why Not Use Native Metavision Python Here

The current KV260 image does not have the Metavision Python SDK modules installed for the custom app path. The official Metavision docs still guide the design:

- SDK/HAL recording is a raw stream operation through `I_EventsStream::log_raw_data()` or `Camera.start_recording(...)`.
- Metavision Viewer can record with `-o`.
- Event files can later be opened through the SDK using RAW/DAT/HDF5 readers when the proper SDK environment exists.

So this repo keeps the stable live capture format:

```text
event_YYYYMMDD_HHMMSS.pse2.raw
event_YYYYMMDD_HHMMSS.pse2.raw.json
```

The `.raw` file is the raw PSE2/EVT2.1 payload stream from the KV260 V4L2 node. The JSON sidecar records device, format, request metadata, byte counters, buffer counters, queue depth, and drop/write-error counters.

## Board API Files

```text
scripts/kv260-event-camera-api.py
scripts/kv260-event-camera-api.sh
```

The API imports the existing GUI recorder module:

```text
scripts/kv260-event-camera-app.py
```

The GUI class now supports:

```text
preview_enabled=False
count_events=False
```

That is what the API uses for recording-first behavior.

## Start And Stop The API On The KV260

Start:

```sh
cd /home/petalinux/Projects/kria-kv260-starter
./scripts/kv260-event-camera-api.sh start
```

Status:

```sh
./scripts/kv260-event-camera-api.sh status
```

Stop:

```sh
./scripts/kv260-event-camera-api.sh stop
```

Tail the API log:

```sh
./scripts/kv260-event-camera-api.sh tail
```

Defaults:

```text
host: 0.0.0.0
port: 8765
record dir: /home/petalinux/event_recordings
device: /dev/video0
auth: off unless KV260_EVENT_API_TOKEN is set
```

Optional token:

```sh
KV260_EVENT_API_TOKEN='change-this-token' ./scripts/kv260-event-camera-api.sh start
```

Clients then send either:

```text
Authorization: Bearer change-this-token
```

or:

```text
X-KV260-Token: change-this-token
```

## API Endpoints

Health/status:

```http
GET /api/v1/status
GET /api/v1/health
```

Start recording:

```http
POST /api/v1/record/start
```

Example JSON body:

```json
{
  "prefix": "illumination",
  "filename": "",
  "folder": "",
  "device": "/dev/video0",
  "takeover": true,
  "force_takeover": false,
  "count_events": false,
  "metadata": {
    "arduino_port": "COM3",
    "light_command": "ON",
    "sample": "test-001"
  }
}
```

Stop recording and close the stream:

```http
POST /api/v1/record/stop
```

Example body:

```json
{
  "close_stream": true
}
```

List recordings:

```http
GET /api/v1/recordings?limit=20
```

Download a recording:

```http
GET /api/v1/recordings/download?path=<recording-path>
```

The path may be absolute under `/home/petalinux/event_recordings` or relative to that folder.

## PowerShell Examples

Status:

```powershell
$Board = "http://192.168.1.100:8765"
Invoke-RestMethod "$Board/api/v1/status"
```

Start:

```powershell
$Body = @{
  prefix = "illumination"
  takeover = $true
  count_events = $false
  metadata = @{
    arduino_port = "COM3"
    trial = "001"
  }
} | ConvertTo-Json -Depth 6

Invoke-RestMethod -Method Post -ContentType "application/json" -Body $Body "$Board/api/v1/record/start"
```

Stop:

```powershell
$Stop = @{ close_stream = $true } | ConvertTo-Json
$Result = Invoke-RestMethod -Method Post -ContentType "application/json" -Body $Stop "$Board/api/v1/record/stop"
$Result.stopped_recording.path
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

## Windows Arduino Client

Client script:

```text
scripts/windows/KV260EventExperimentClient.py
```

On Windows, copy/use the script from the installed control-center folder or from this repo.

Install `pyserial` only if Arduino serial control is needed:

```powershell
python -m pip install pyserial
```

Check board status:

```powershell
python .\KV260EventExperimentClient.py --board-url http://192.168.1.100:8765 status
```

Run an experiment where recording starts before the light changes:

```powershell
python .\KV260EventExperimentClient.py `
  --board-url http://192.168.1.100:8765 `
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

Default timing mode:

```text
record-then-light
```

This starts KV260 recording first, waits `--pre-trigger-seconds`, then sends the Arduino light-on command. This is the safer default for event cameras because the illumination edge can happen very quickly.

Alternative mode:

```powershell
python .\KV260EventExperimentClient.py `
  --board-url http://192.168.1.100:8765 `
  run `
  --light-mode light-then-record `
  --arduino-port COM3 `
  --light-on "ON" `
  --settle-seconds 0.5 `
  --seconds 5
```

Use this when the light should stabilize before recording.

## Python API Usage On Windows

```python
from KV260EventExperimentClient import KV260ApiClient
import time

api = KV260ApiClient("http://192.168.1.100:8765")

api.start({
    "prefix": "illumination",
    "takeover": True,
    "count_events": False,
    "metadata": {"trial": "001", "light": "on"},
})

time.sleep(5)
result = api.stop(close_stream=True)
raw_path = result["stopped_recording"]["path"]
json_path = result["stopped_recording"]["meta_path"]

api.download(raw_path, r"C:\Users\Administrator\Downloads\kv260-events")
api.download(json_path, r"C:\Users\Administrator\Downloads\kv260-events")
```

## Arduino Protocol

The client does not assume a specific Arduino sketch. It writes the command string you give it.

Common simple sketch protocol:

```text
ON\n
OFF\n
PWM 128\n
```

The Python client appends a newline by default. Use `--no-newline` if the Arduino sketch expects raw bytes without newline.

## Correctness And Limits

Recording path:

```text
V4L2 DQBUF -> bytes copy -> V4L2 QBUF -> bounded writer queue -> disk
```

The API disables preview, so GUI display speed cannot slow the experiment recorder.

The API disables event counting by default, so the capture loop does not spend CPU decoding event vectors. Enable `--count-events` only when live event-rate stats are worth the CPU cost.

The API still cannot make the physical camera stream lossless under all possible event-rate bursts. It records every payload successfully dequeued and accepted by the bounded writer queue. The JSON sidecar reports writer drops and write errors.

## One Camera Owner Rule

Only one of these should own `/dev/video0` at a time:

```text
KV260 Event Camera GUI
native metavision_viewer
headless API recorder
```

`takeover=true` asks the GUI/native viewer helpers to stop first. If some unrelated process still owns `/dev/video0`, the API returns an error unless `force_takeover=true` is requested.

## References

- Prophesee Metavision event recording guide: `https://docs.prophesee.ai/stable/guides/events_recording.html`
- Prophesee event file opening guide: `https://docs.prophesee.ai/stable/guides/event_file_opening.html`
- Prophesee Metavision Viewer sample: `https://docs.prophesee.ai/stable/samples/modules/stream/viewer.html`
- Prophesee RAW file format guide: `https://docs.prophesee.ai/stable/data/file_formats/raw.html`
- Local recording robustness note: `references/kv260-recording-robustness.md`
- Local custom viewer note: `references/kv260-event-camera-app.md`
