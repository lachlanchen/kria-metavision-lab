# KV260 View Of Windows Arduino Setup

Updated: 2026-06-06

This note records what the KV260 board should know about the Windows host, Arduino, Prophesee event camera, and related Windows repositories.

It is based on the Windows-side handoff note:

```text
C:\Users\Administrator\Projects\DualLampHI\docs\kv260_windows_arduino_handoff_cn.md
```

and verified from this KV260 board over LAN SSH to Windows.

## Current Network Situation

KV260 board:

```text
hostname: xilinx-kv260-starterkit-20222
user: petalinux
IPv4: 192.168.1.250/24
interface: eth0
repo: /home/petalinux/Projects/kria-kv260-starter
```

Windows host:

```text
hostname: CSG1175-P
IPv4: 192.168.1.166
network: 192.168.1.0/24
user: Administrator
projects root: C:\Users\Administrator\Projects
```

Connectivity verified from KV260:

```text
ping 192.168.1.166: OK
Windows SSH: OK
```

Use IP addresses instead of relying on hostname resolution:

```text
Windows from KV260: 192.168.1.166
KV260 from Windows: 192.168.1.250
```

## Device Roles

```text
KV260
  connected to Prophesee event camera
  records event data from /dev/video0
  owns the event recording API

Windows
  connected to Arduino by USB serial
  owns arduino-cli, Arduino serial, and the illumination-control GUI/API
  can call the KV260 event recording API

Arduino UNO
  no IP address
  visible only as a Windows COM port when connected
  drives LED/lamp modulation
```

Important point:

```text
The Arduino is not a network device. KV260 cannot talk to Arduino directly.
KV260 can only talk to Windows, and Windows talks to Arduino over USB serial.
```

## Current Arduino Situation

Windows-side note says the Arduino UNO was previously uploaded on:

```text
board: Arduino UNO
FQBN: arduino:avr:uno
previous port: COM3
```

Current Windows detection in that note:

```text
only COM1 Unknown
```

Interpretation:

```text
Arduino UNO is currently not detected as COM3.
```

Before controlled experiments, reconnect/check Arduino on Windows:

```powershell
arduino-cli board list
```

Expected when healthy:

```text
COM3 ... Arduino UNO ... arduino:avr:uno
```

If only `COM1 Unknown` appears, fix the USB cable/port/driver/use conflict first. KV260 cannot control Arduino through Windows until Windows sees the Arduino serial port.

## Existing Arduino Sketch Context

Windows-side note identifies the current sketch:

```text
C:\Users\Administrator\Projects\DualLampHI\firmware\dual_led_direct_timer1\dual_led_direct_timer1.ino
```

Previously uploaded behavior:

```text
D9  -> LED A
D10 -> LED B
GND -> both LED negative pins
```

LED behavior:

```text
LED A: dark -> bright -> dark
LED B: bright -> dark -> bright
relationship: dB(t) = 1 - dA(t)
modulation frequency: 0.5 Hz
cycle period: about 2 seconds
PWM carrier: about 62.5 kHz on D9/D10 using Timer1
```

## Two Valid Experiment Modes

### Mode A: Autonomous Arduino, KV260 Records

This is the recommended first experiment.

Flow:

```text
1. Windows uploads Arduino sketch once.
2. Arduino resets and auto-runs LED modulation.
3. KV260 records Prophesee event stream.
4. Event pattern reveals LED modulation and phase after analysis.
```

Benefits:

```text
No network service required.
No serial command protocol required.
Works even if KV260 cannot command Windows.
```

Limitation:

```text
KV260 recording start and Arduino modulation phase are not exactly locked.
Infer phase from the recorded event pattern or from a visible optical sync LED.
```

### Mode B: Controlled Windows Arduino Service

Flow:

```text
KV260 or Windows controller
  -> sends HTTP command to Windows Arduino service
  -> Windows writes serial command to Arduino COM3
  -> Arduino changes LEDs
  -> KV260 records event data
```

Because the KV260 recorder already uses port `8765`, use this clearer port split:

```text
KV260 event recording API:   http://192.168.1.250:8765
Windows Arduino control API: http://192.168.1.166:8780
```

Using `8765` on Windows would technically work because it is a different host, but `8780` avoids confusing the two services.

Recommended Windows Arduino API endpoints:

```text
GET  http://192.168.1.166:8780/api/v1/arduino/status
GET  http://192.168.1.166:8780/api/v1/arduino/boards
POST http://192.168.1.166:8780/api/v1/arduino/serial/connect
POST http://192.168.1.166:8780/api/v1/arduino/serial/command
POST http://192.168.1.166:8780/api/v1/light/on
POST http://192.168.1.166:8780/api/v1/light/off
POST http://192.168.1.166:8780/api/v1/light/pwm
POST http://192.168.1.166:8780/api/v1/experiment/run
```

The Windows firewall must allow inbound access to the chosen port if KV260 will call the Windows API directly.

## Preferred Control Direction

There are two possible directions:

### Preferred for first controlled version: Windows orchestrates both

```text
Windows controls Arduino serial.
Windows calls KV260 recording API.
Windows downloads event files.
```

This is simplest because the Arduino is physically attached to Windows.

KV260 API:

```text
http://192.168.1.250:8765
```

Start API on KV260:

```sh
cd /home/petalinux/Projects/kria-kv260-starter
./scripts/kv260-event-camera-api.sh start
```

Windows can use:

```text
scripts/windows/KV260EventExperimentClient.py
```

Example:

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
  --output-dir "$env:USERPROFILE\Downloads\kv260-events"
```

### Alternative: KV260 commands Windows

```text
KV260 calls Windows Arduino API at 192.168.1.166:8780.
Windows API writes to Arduino COM3.
KV260 starts/stops its own event recording.
```

This is useful if the board should be the experiment master. It requires the Windows Arduino API service to be running and reachable through Windows firewall.

## KV260 Event Recording API

Board-side files:

```text
scripts/kv260-event-camera-api.py
scripts/kv260-event-camera-api.sh
references/kv260-remote-recording-api.md
```

Start:

```sh
cd /home/petalinux/Projects/kria-kv260-starter
./scripts/kv260-event-camera-api.sh start
```

Status:

```sh
./scripts/kv260-event-camera-api.sh status
curl http://127.0.0.1:8765/api/v1/status
```

External Windows URL:

```text
http://192.168.1.250:8765
```

The API records:

```text
/home/petalinux/event_recordings/*.pse2.raw
/home/petalinux/event_recordings/*.pse2.raw.json
```

Only one process can own `/dev/video0`; use `takeover=true` when starting API recording.

## Windows Repository Map

Verified from Windows host `CSG1175-P` over SSH.

All are under:

```text
C:\Users\Administrator\Projects
```

### V-SPICE / polarizer

```text
local path: C:\Users\Administrator\Projects\polarizer
branch: main
remote: git@github.com:lachlanchen/V-SPICE.git
purpose: voltage-coded spectro-polarimetric imaging, optical path, LCD/light-valve, phase/polarization/spectrum derivations
```

### DualLampHI

```text
local path: C:\Users\Administrator\Projects\DualLampHI
branch: main
remote: git@github.com:lachlanchen/DualLampHI.git
purpose: dual-lamp / dual-LED illumination modulation, Arduino firmware, wiring docs
```

Important files from Windows note:

```text
firmware\dual_led_direct_timer1\dual_led_direct_timer1.ino
publication\dual_led_uploaded_setup_cn.pdf
publication\dual_led_direct_arduino_timer1_cn.pdf
publication\dual_led_elegant_minimal_wiring_cn.pdf
docs\kv260_windows_arduino_handoff_cn.md
```

### OpenHI3.0

```text
local path: C:\Users\Administrator\Projects\OpenHI3.0
branch: main
remote: https://github.com/lachlanchen/OpenHI3.0.git
purpose: related OpenHI / dual-lamp idea repository for future hyperspectral/event-camera context
```

### OpenHI2.0

```text
local path: C:\Users\Administrator\Projects\OpenHI2.0
branch: main
remote: https://github.com/lachlanchen/OpenHI2.0.git
purpose: earlier OpenHI / dual-lamp idea repository for historical context
```

Other Windows project folders observed:

```text
confocal
openhi-materials
petalinux
```

## Minimum Metadata To Record Per Experiment

```text
experiment name
KV260 timestamp
event recording filename
event recording JSON sidecar
camera model / sensor module
Arduino sketch repo + commit
Arduino COM port
Arduino FQBN
LED wiring mode
modulation frequency
LED A/B physical positions
Windows hostname/IP
KV260 hostname/IP
```

## Immediate Action

For the next practical experiment:

```text
1. On Windows, reconnect Arduino UNO.
2. Run arduino-cli board list.
3. Confirm Arduino appears as COM3 or update the port.
4. If using autonomous mode, ensure LEDs are visibly alternating.
5. Start KV260 event recording API or GUI recording.
6. Record event stream while LEDs modulate.
```

If controlled mode is needed next:

```text
1. Implement/start Windows Arduino API at 192.168.1.166:8780.
2. Open Windows firewall for that port.
3. Keep KV260 event API at 192.168.1.250:8765.
4. Use Windows as experiment master first, because Arduino is attached to Windows.
```

## Cross References

```text
references/windows-arduino-codex-handoff.md
references/kv260-arduino-cli-control-api.md
references/kv260-remote-recording-api.md
references/kv260-event-camera-app.md
```
