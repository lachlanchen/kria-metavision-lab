# Arduino CLI Light-Control API And GUI Design

Updated: 2026-06-06

This note documents how to add Arduino control to the current KV260/Windows experiment workflow.

Target workflow:

```text
Windows host
  USB Arduino for light illumination
  Arduino CLI for sketch/core/library/upload/bootloader operations
  Serial API for real-time light commands
  GUI for lab operation
        |
        | HTTP
        v
KV260
  Headless event recording API
  Prophesee event camera on /dev/video0
```

## Conclusion

Yes, this is a good direction.

Recommended architecture:

| Layer | Runs on | Purpose |
| --- | --- | --- |
| Arduino CLI | Windows | Board discovery, core install, library install, compile, upload, optional bootloader burn |
| Arduino serial control API | Windows | Low-latency light on/off/PWM/pattern commands |
| KV260 recording API | KV260 | Start/stop event recording and download `.pse2.raw` + `.json` |
| Control Center GUI | Windows | One screen for Arduino setup, light control, event recording, and experiment execution |

Do not put Arduino control on the KV260 unless the Arduino is physically connected to the KV260 USB port. In the current lab setup, the Arduino is connected to Windows, so the Arduino API should run on Windows.

## Important Design Separation

Arduino has two different control modes:

| Mode | Tool | Timing | Use |
| --- | --- | --- | --- |
| Build/upload firmware | `arduino-cli` | Slow, seconds | Install cores, compile sketch, upload sketch |
| Runtime light commands | Serial API, such as Python `pyserial` or .NET `SerialPort` | Fast, milliseconds | `ON`, `OFF`, `PWM 128`, trigger patterns |

`arduino-cli monitor` can open a serial monitor, but it is terminal-oriented. For a robust API, use direct serial I/O for runtime light commands and reserve `arduino-cli` for build/upload/system operations.

## Official Arduino CLI Capabilities

Arduino CLI provides the command-line equivalent of Arduino IDE features. The official getting-started guide shows:

```sh
arduino-cli config init
arduino-cli sketch new MyFirstSketch
arduino-cli core update-index
arduino-cli board list
arduino-cli core install arduino:samd
arduino-cli compile --fqbn arduino:samd:mkr1000 MyFirstSketch
arduino-cli upload -p /dev/ttyACM0 --fqbn arduino:samd:mkr1000 MyFirstSketch
```

For this project, the most important commands are:

| Operation | Command pattern |
| --- | --- |
| Check CLI | `arduino-cli version --json` |
| Initialize config | `arduino-cli config init` |
| Dump config | `arduino-cli config dump --json` |
| Update core index | `arduino-cli core update-index` |
| List boards | `arduino-cli board list --json` |
| Search boards | `arduino-cli board listall <query>` |
| Install core | `arduino-cli core install <core>` |
| Install library | `arduino-cli lib install <library>` |
| Compile | `arduino-cli compile --fqbn <fqbn> <sketch-dir>` |
| Compile and export binaries | `arduino-cli compile --fqbn <fqbn> --export-binaries <sketch-dir>` |
| Upload | `arduino-cli upload -p <port> --fqbn <fqbn> <sketch-dir>` |
| Compile then upload | `arduino-cli compile --fqbn <fqbn> --upload -p <port> <sketch-dir>` |
| Serial monitor | `arduino-cli monitor -p <port> --config baudrate=115200` |
| Burn bootloader | `arduino-cli burn-bootloader -b <fqbn> -P <programmer> [-p <port>]` |

`--json` is useful wherever supported because the GUI/API can parse structured output rather than screen text.

## Windows Installation Plan

Install Arduino CLI on Windows, not the KV260, when the Arduino is attached to Windows.

Options:

| Method | Recommendation |
| --- | --- |
| Windows MSI | Best normal GUI-user install |
| Windows exe / zip | Good for repo-local portable setup |
| Git Bash install script | Acceptable if Git for Windows is installed |

Recommended Windows setup flow:

```powershell
arduino-cli version
arduino-cli config init
arduino-cli core update-index
arduino-cli board list --json
```

If the board is an Arduino Uno:

```powershell
arduino-cli core install arduino:avr
arduino-cli compile --fqbn arduino:avr:uno C:\path\to\LightController
arduino-cli upload -p COM3 --fqbn arduino:avr:uno C:\path\to\LightController
```

If the board is unknown, first run:

```powershell
arduino-cli board list --json
arduino-cli board listall uno
arduino-cli board listall nano
```

Then choose the matching FQBN.

## Reproducible Sketch Project

Use a dedicated sketch folder under the Windows control-center install area or repo cache:

```text
C:\Users\Administrator\Projects\petalinux\kv260-remote-gui\arduino\LightController
```

Preferred files:

```text
LightController/
  LightController.ino
  sketch.yaml
  README.md
```

`sketch.yaml` should store reproducible board/profile data:

```yaml
profiles:
  uno:
    fqbn: arduino:avr:uno
    platforms:
      - platform: arduino:avr
    libraries: []
default_profile: uno
```

This avoids depending only on GUI memory for FQBN and core choices.

## Recommended Arduino Light Firmware

Use a simple line-based serial protocol. Keep it boring and deterministic:

```text
PING
ON
OFF
PWM 0..255
PULSE <on_ms> <off_ms> <count>
PATTERN <name>
STATUS
```

Recommended response format:

```text
OK <command>
ERR <reason>
STATE light=<0|1> pwm=<0..255> pattern=<name>
```

This works with Python, PowerShell, .NET, Arduino Serial Monitor, and `arduino-cli monitor`.

Sketch behavior:

- Configure LED/illumination control pins in constants at top of sketch.
- On boot, set output to safe off state.
- Accept newline-terminated commands.
- Reply to every command with `OK` or `ERR`.
- Avoid long blocking delays except inside explicitly requested pulse patterns.
- If precise timing matters, use `millis()` state machines instead of long `delay()`.

## Windows Arduino API Design

Implement a local Windows API service:

```text
http://127.0.0.1:8780
```

It should expose Arduino operations and optionally call the KV260 recording API.

Recommended service implementation:

| Language | Why |
| --- | --- |
| Python + FastAPI or Flask | Fast to build, works with `subprocess` + `pyserial` |
| PowerShell/.NET WinForms app only | Fine for GUI, less clean for HTTP service |
| C#/.NET | Best polished Windows app later, more initial work |

Pragmatic first implementation:

```text
Python service + current Windows Control Center GUI calls it
```

### API Endpoints

Health:

```http
GET /api/v1/arduino/status
```

Return:

```json
{
  "ok": true,
  "arduino_cli": "1.5.0",
  "serial_connected": true,
  "port": "COM3",
  "fqbn": "arduino:avr:uno"
}
```

Board discovery:

```http
GET /api/v1/arduino/boards
```

Internally:

```powershell
arduino-cli board list --json
```

Core install:

```http
POST /api/v1/arduino/core/install
```

Body:

```json
{
  "core": "arduino:avr"
}
```

Library install:

```http
POST /api/v1/arduino/library/install
```

Body:

```json
{
  "library": "FastLED"
}
```

Compile:

```http
POST /api/v1/arduino/sketch/compile
```

Body:

```json
{
  "sketch_dir": "C:/Users/Administrator/Projects/petalinux/kv260-remote-gui/arduino/LightController",
  "fqbn": "arduino:avr:uno",
  "export_binaries": true
}
```

Upload:

```http
POST /api/v1/arduino/sketch/upload
```

Body:

```json
{
  "sketch_dir": "C:/Users/Administrator/Projects/petalinux/kv260-remote-gui/arduino/LightController",
  "fqbn": "arduino:avr:uno",
  "port": "COM3"
}
```

Compile and upload:

```http
POST /api/v1/arduino/sketch/compile-upload
```

Runtime connect:

```http
POST /api/v1/arduino/serial/connect
```

Body:

```json
{
  "port": "COM3",
  "baud": 115200
}
```

Runtime command:

```http
POST /api/v1/arduino/serial/command
```

Body:

```json
{
  "command": "PWM 180",
  "timeout_ms": 500
}
```

Light shortcuts:

```http
POST /api/v1/light/on
POST /api/v1/light/off
POST /api/v1/light/pwm
POST /api/v1/light/pulse
```

Experiment sequence:

```http
POST /api/v1/experiment/run
```

Body:

```json
{
  "kv260_url": "http://192.168.1.100:8765",
  "record_prefix": "illumination",
  "mode": "record-then-light",
  "pre_trigger_ms": 100,
  "duration_ms": 5000,
  "light_on": "ON",
  "light_off": "OFF",
  "download_dir": "C:/Users/Administrator/Downloads/kv260-events",
  "metadata": {
    "trial": "001",
    "illumination": "white-led"
  }
}
```

This endpoint should call the existing KV260 recording API:

```text
POST http://<kv260>:8765/api/v1/record/start
POST http://<kv260>:8765/api/v1/record/stop
GET  http://<kv260>:8765/api/v1/recordings/download
```

## Bootloader Burn Design

Do not present bootloader burn as a normal upload action.

Bootloader burning:

- requires an external programmer for many boards,
- can fail if the wrong FQBN/programmer/port is selected,
- is not needed for normal sketch upload,
- should be treated as an advanced recovery/manufacturing operation.

API endpoint:

```http
POST /api/v1/arduino/bootloader/burn
```

Body:

```json
{
  "fqbn": "arduino:avr:uno",
  "programmer": "atmel_ice",
  "port": "",
  "confirm": "BURN BOOTLOADER"
}
```

The service should reject requests unless:

- `confirm` exactly matches `BURN BOOTLOADER`,
- the user selected an explicit programmer,
- the GUI shows the exact command before running it,
- a log file is created.

Internal command:

```powershell
arduino-cli burn-bootloader -b arduino:avr:uno -P atmel_ice
```

Use `-p COMx` only when the programmer/upload protocol requires it.

## GUI Design

Add a new `Arduino / Light` tab to the Windows KV260 Control Center.

### Top Status Strip

Show:

```text
Arduino CLI: found / missing
Arduino: COM3, arduino:avr:uno
Serial: connected / disconnected
KV260 API: online / offline
Last upload: success / failed
```

Buttons:

```text
Refresh
Install Arduino CLI
Open Arduino Logs
```

### Devices Panel

Controls:

- board list table from `arduino-cli board list --json`,
- port selector,
- FQBN selector,
- core selector,
- baud selector,
- connect/disconnect serial.

Buttons:

```text
Detect Boards
Update Index
Install Core
Save Profile
```

### Light Control Panel

Controls:

- `ON`
- `OFF`
- PWM slider `0..255`
- pulse duration inputs,
- pulse count,
- named pattern dropdown.

Buttons should send serial commands, not upload firmware.

### Sketch Panel

Controls:

- sketch folder,
- firmware template dropdown,
- code editor button,
- compile button,
- upload button.

Buttons:

```text
Create Light Sketch
Compile
Upload
Compile + Upload
Serial Monitor
```

### Experiment Panel

Controls:

- KV260 API URL,
- record prefix,
- duration,
- pre-trigger delay,
- mode: `record-then-light` or `light-then-record`,
- download folder,
- metadata fields.

Main button:

```text
Run Light + Event Recording
```

Sequence:

```text
1. ensure Arduino serial connected
2. ensure KV260 API reachable
3. start KV260 recording
4. wait pre-trigger delay
5. send Arduino light command
6. wait duration
7. stop KV260 recording
8. send Arduino off command
9. download raw/json files
10. show result paths and stats
```

### Advanced Burn Panel

Put this behind an expandable advanced section:

```text
Burn Bootloader
```

Require confirmation text and show the exact command. Do not place this near the normal upload button.

## API Execution Rules

The Arduino API service should:

- run Arduino CLI commands with explicit argument arrays, not string-concatenated shell commands,
- capture stdout/stderr and return structured logs,
- serialize compile/upload/burn operations with a lock,
- close serial before upload because upload often needs the same COM port,
- reopen serial after upload if requested,
- write logs under `%APPDATA%\KV260ControlCenter\arduino-logs`,
- never expose the Windows API outside localhost unless token auth is enabled.

Recommended command wrapper result:

```json
{
  "ok": true,
  "command": ["arduino-cli", "compile", "--fqbn", "arduino:avr:uno", "LightController"],
  "exit_code": 0,
  "stdout": "...",
  "stderr": "",
  "elapsed_ms": 2100
}
```

## Integration With Existing Repo

Current existing files:

```text
scripts/windows/KV260EventExperimentClient.py
scripts/kv260-event-camera-api.py
scripts/kv260-event-camera-api.sh
references/kv260-remote-recording-api.md
```

Next implementation files should be:

```text
scripts/windows/KV260ArduinoControlApi.py
scripts/windows/KV260ArduinoControlCenter.ps1
scripts/windows/arduino/LightController/LightController.ino
scripts/windows/arduino/LightController/sketch.yaml
references/kv260-arduino-cli-control-api.md
```

The existing Windows Control Center can call the local Arduino API, or the Arduino GUI can be a separate window first. The separate-window path is lower risk for the first version; merge it into the Control Center after the API behavior is stable.

## Recommended First Implementation

Stage 1:

- Windows Python API with `arduino-cli` subprocess wrapper.
- `GET /api/v1/arduino/boards`.
- `POST /api/v1/arduino/serial/connect`.
- `POST /api/v1/arduino/serial/command`.
- `POST /api/v1/experiment/run`, reusing the current KV260 recording API.
- Simple `LightController.ino`.

Stage 2:

- Compile/upload endpoints.
- GUI sketch folder/profile selector.
- Install core/library helpers.

Stage 3:

- Bootloader burn advanced panel.
- Full logs viewer.
- Optional gRPC daemon integration if direct CLI subprocess becomes limiting.

## Why Not Start With `arduino-cli daemon`

Arduino CLI can run as a gRPC daemon on port `50051`. That is useful for deeper tool integrations, but it is not the best first version here:

- The existing Windows Control Center is not a gRPC client.
- HTTP is easier for PowerShell, Python, and browser-based UI.
- The API still needs serial runtime commands and KV260 recording orchestration, which are outside raw Arduino CLI build/upload.

Use normal `arduino-cli` subprocess calls first. Add daemon/gRPC only if repeated command startup overhead or integration complexity becomes a measured problem.

## Safety Notes

- Uploading a sketch resets many Arduino boards and temporarily disconnects serial.
- Close the serial runtime connection before upload.
- Reopen serial after upload and wait for the board boot delay.
- Keep the light output off during firmware upload unless the hardware is designed otherwise.
- Bootloader burn is advanced and should require explicit confirmation.
- If the light source can damage a sample or camera, add a maximum-on timer in both Arduino firmware and the Windows API.

## References

- Arduino CLI installation: `https://docs.arduino.cc/arduino-cli/installation/`
- Arduino CLI getting started: `https://docs.arduino.cc/arduino-cli/getting-started/`
- Arduino CLI board list: `https://docs.arduino.cc/arduino-cli/commands-reference/arduino-cli_board_list/`
- Arduino CLI compile: `https://docs.arduino.cc/arduino-cli/commands-reference/arduino-cli_compile/`
- Arduino CLI upload: `https://docs.arduino.cc/arduino-cli/commands-reference/arduino-cli_upload/`
- Arduino CLI monitor: `https://docs.arduino.cc/arduino-cli/commands-reference/arduino-cli_monitor/`
- Arduino CLI burn bootloader: `https://docs.arduino.cc/arduino-cli/commands-reference/arduino-cli_burn-bootloader/`
- Arduino CLI daemon: `https://docs.arduino.cc/arduino-cli/commands-reference/arduino-cli_daemon`
- Arduino sketch project file: `https://docs.arduino.cc/arduino-cli/sketch-project-file/`
- Existing KV260 remote recording API: `references/kv260-remote-recording-api.md`
