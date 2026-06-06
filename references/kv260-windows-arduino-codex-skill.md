# KV260 Windows Arduino Codex Skill

Updated: 2026-06-06

This note documents the local Codex skill created for the KV260 / Windows / Arduino lab workflow.

## Skill Location

Installed local skill:

```text
/home/petalinux/.codex/skills/kv260-windows-arduino
```

Primary file:

```text
/home/petalinux/.codex/skills/kv260-windows-arduino/SKILL.md
```

The skill is installed under `/home/petalinux/.codex/skills` so future Codex sessions on this board can discover it automatically.

Versioned skill source in this repository:

```text
skills/kv260-windows-arduino
```

When changing the skill, update both the installed copy and the versioned copy, then validate the installed copy.

## Trigger Purpose

Use this skill when a Codex session needs to:

```text
coordinate KV260 event recording with Windows Arduino light control
inspect the KV260 / Windows / Arduino LAN topology
start, stop, or call the KV260 recording API
probe Windows Arduino CLI and COM-port state
reason about Arduino CLI compile/upload/serial-control workflows
use the four related Windows/KV260 research repos
diagnose port conflicts, /dev/video0 ownership, Windows firewall, or phase-sync issues
```

## Skill File Tree

```text
kv260-windows-arduino/
  SKILL.md
  agents/
    openai.yaml
  references/
    topology.md
    kv260-recording-api.md
    windows-arduino-control.md
    repositories.md
    conflicts.md
    session-memory.md
  scripts/
    kv260-lab-status.sh
    kv260-record-once.sh
    fetch-windows-codex-session.sh
    windows-arduino-probe.sh
```

## Bundled References

| File | Purpose |
| --- | --- |
| `references/topology.md` | Machine identities, IPs, roles, and reachability checks |
| `references/kv260-recording-api.md` | KV260 recording API endpoints and `/dev/video0` ownership rules |
| `references/windows-arduino-control.md` | Arduino CLI usage, serial light protocol, and Windows Arduino API design |
| `references/repositories.md` | Four repo paths, remotes, commits, and important files |
| `references/conflicts.md` | Known failure modes: COM port, port split, firewall, camera ownership, phase ambiguity, disk use |
| `references/session-memory.md` | How to inspect Codex JSONL safely and keep Windows/KV260 sessions cross-aware |

## Paired Windows Skill

Windows-side local skill:

```text
C:\Users\Administrator\.codex\skills\kv260-arduino-event-control\SKILL.md
```

Versioned Windows-side skill source:

```text
C:\Users\Administrator\Projects\DualLampHI\skills\kv260-arduino-event-control
```

Latest Windows-side documentation reported by the paired session:

```text
C:\Users\Administrator\Projects\DualLampHI\docs\kv260_arduino_connection_control_methods_cn.md
C:\Users\Administrator\Projects\DualLampHI\skills\kv260-arduino-event-control\references\connection_control.md
```

Windows-side commit reported by the paired session:

```text
5c7aa69 docs: add KV260 Arduino control methods skill
```

## Codex Session History

Codex JSONL can be inspected when the user explicitly asks, but raw transcript content should not be copied into this repo or into skills.

Known session files:

```text
Board:
/home/petalinux/.codex/sessions/2026/05/26/rollout-2026-05-26T07-14-26-019e64a3-0950-7491-8e3d-57f8541dd1b7.jsonl

Windows:
C:\Users\Administrator\.codex\sessions\2026\05\26\rollout-2026-05-26T20-36-37-019e6449-7a73-74d3-bd33-154399427cc5.jsonl
```

Use JSONL as an audit source only. Durable memory belongs in `AGENTS.md`, skill references, and repo docs.

## Bundled Scripts

### `kv260-lab-status.sh`

Read-only status script for the board-side lab state.

Checks:

```text
KV260 hostname and IPv4
disk usage
Windows ping
Windows SSH hostname
KV260 event API status
viewer status
/dev/video0 owner
four related repo commits and branch state
```

Run:

```sh
/home/petalinux/.codex/skills/kv260-windows-arduino/scripts/kv260-lab-status.sh
```

Latest observed result:

```text
KV260 hostname: xilinx-kv260-starterkit-20222
KV260 IPv4: 192.168.1.250/24
Windows ping 192.168.1.166: OK
Windows SSH hostname: CSG1175-P
KV260 event API: stopped
board desktop viewer: stopped
windows-x11 viewer: stopped
/dev/video0 owners: none
```

Repo commits observed:

```text
polarizer:  c82ee94
DualLampHI: 7966bb6
OpenHI3.0:  140eb3f
OpenHI2.0:  8b4a4fc
```

### `windows-arduino-probe.sh`

Read-only Windows Arduino probe through Windows SSH.

Checks:

```text
Windows hostname
arduino-cli version
arduino-cli board list
```

Run:

```sh
/home/petalinux/.codex/skills/kv260-windows-arduino/scripts/windows-arduino-probe.sh
```

Latest observed result:

```text
Windows hostname: CSG1175-P
arduino-cli: 1.4.1
board list: COM1 serial Serial Port Unknown
```

Meaning:

```text
Arduino UNO is still not visible as COM3.
Fix Windows USB/driver/port detection before controlled Arduino serial experiments.
```

### `kv260-record-once.sh`

One-shot KV260 recording helper.

Behavior:

```text
starts KV260 event API if needed
starts recording with takeover=true and count_events=false
waits N seconds
stops recording
prints JSON result
```

Run:

```sh
/home/petalinux/.codex/skills/kv260-windows-arduino/scripts/kv260-record-once.sh --seconds 2 --prefix skill_smoke
```

This script changes recording state and may stop GUI/native viewers through `takeover=true`. Use it only when recording is intended.

## Communication Methods

### KV260 To Windows

Ping:

```sh
ping -c 2 192.168.1.166
```

SSH:

```sh
ssh -i /home/petalinux/.ssh/id_dropbear_rsa -y Administrator@192.168.1.166 "powershell -NoProfile -Command \"hostname\""
```

Note: the PetaLinux Dropbear SSH client may ignore OpenSSH options such as `BatchMode=yes`.

### Windows To KV260 Event API

KV260 API URL:

```text
http://192.168.1.250:8765
```

Status:

```powershell
Invoke-RestMethod "http://192.168.1.250:8765/api/v1/status"
```

Start recording:

```powershell
$Body = @{
  prefix = "illumination"
  takeover = $true
  count_events = $false
  metadata = @{ source = "windows-arduino" }
} | ConvertTo-Json -Depth 8

Invoke-RestMethod -Method Post -ContentType "application/json" -Body $Body "http://192.168.1.250:8765/api/v1/record/start"
```

Stop recording:

```powershell
$Stop = @{ close_stream = $true } | ConvertTo-Json
Invoke-RestMethod -Method Post -ContentType "application/json" -Body $Stop "http://192.168.1.250:8765/api/v1/record/stop"
```

### Windows Arduino Control

Recommended future Windows API:

```text
http://192.168.1.166:8780
```

Keep port `8780` for Windows Arduino control, because KV260 event recording already uses port `8765`.

Core future endpoints:

```text
GET  /api/v1/arduino/status
GET  /api/v1/arduino/boards
POST /api/v1/arduino/serial/connect
POST /api/v1/arduino/serial/command
POST /api/v1/light/on
POST /api/v1/light/off
POST /api/v1/light/pwm
POST /api/v1/experiment/run
```

## Arduino CLI Methods

Run on Windows:

```powershell
arduino-cli version --json
arduino-cli config init
arduino-cli core update-index
arduino-cli board list --json
arduino-cli core install arduino:avr
arduino-cli compile --fqbn arduino:avr:uno C:\path\to\LightController
arduino-cli upload -p COM3 --fqbn arduino:avr:uno C:\path\to\LightController
```

Current board-specific sketch:

```text
Windows:
C:\Users\Administrator\Projects\DualLampHI\firmware\dual_led_direct_timer1\dual_led_direct_timer1.ino

KV260 clone:
/home/petalinux/Projects/DualLampHI/firmware/dual_led_direct_timer1/dual_led_direct_timer1.ino
```

Bootloader burn is advanced and should not be exposed as a normal upload action.

## Known Conflicts

```text
Arduino has no IP address.
Arduino COM3 is not currently confirmed; Windows sees only COM1 Unknown.
KV260 event API should use 192.168.1.250:8765.
Windows Arduino API should use 192.168.1.166:8780.
Windows firewall may block inbound KV260 -> Windows control.
Only one process can own /dev/video0.
Autonomous LED modulation is not phase-locked to event recording without a sync signal.
```

## Validation

Skill validation:

```sh
python3 /home/petalinux/.codex/skills/.system/skill-creator/scripts/quick_validate.py /home/petalinux/.codex/skills/kv260-windows-arduino
```

Result:

```text
Skill is valid.
```

Script smoke checks completed:

```text
kv260-lab-status.sh: passed
windows-arduino-probe.sh: passed
```

`kv260-record-once.sh` was not run during skill creation because it intentionally changes camera recording state.

### `fetch-windows-codex-session.sh`

Fetches Windows Codex JSONL into the ignored board-side cache:

```text
/home/petalinux/Projects/kria-kv260-starter/private/windows-codex-history/
```

Run:

```sh
/home/petalinux/.codex/skills/kv260-windows-arduino/scripts/fetch-windows-codex-session.sh \
  --session-id 019e6449-7a73-74d3-bd33-154399427cc5
```

This script is for targeted recovery only. Do not commit raw JSONL.

## Canonical Repo Docs

Detailed project docs remain in:

```text
references/kv260-windows-arduino-situation.md
references/windows-arduino-codex-handoff.md
references/kv260-arduino-cli-control-api.md
references/kv260-remote-recording-api.md
```

## Windows Peer Skill Known By KV260

Windows peer skill known by KV260:

```text
name: kv260-arduino-event-control
installed: C:\Users\Administrator\.codex\skills\kv260-arduino-event-control
repo copy: C:\Users\Administrator\Projects\DualLampHI\skills\kv260-arduino-event-control
memory doc: C:\Users\Administrator\Projects\DualLampHI\docs\codex_cross_session_memory_cn.md
```

The two skills should be treated as peers:

```text
KV260 skill:  /home/petalinux/.codex/skills/kv260-windows-arduino
Windows skill: C:\Users\Administrator\.codex\skills\kv260-arduino-event-control
```

When one skill changes machine identity, API ports, repo paths, helper scripts, or experiment-control rules, update the other skill or its reference docs in the same change.

Raw Codex history files and SQLite logs are not the canonical memory. Use curated AGENTS.md, handoff docs, skill files, and helper scripts.

## Board Codex History JSONL

The board-side Codex history file is:

```text
/home/petalinux/.codex/history.jsonl
```

It can help a future session understand recent board-side conversation before deciding how to access hardware. Use only targeted reads such as:

```sh
tail -n 80 /home/petalinux/.codex/history.jsonl
grep -iE 'arduino|com3|recording api|duallamphi|v-spice|preview' /home/petalinux/.codex/history.jsonl | tail -n 80
```

Memory priority remains:

```text
curated AGENTS.md / skill docs / handoff docs
then targeted JSONL context
then verify with actual device and process state
```

Do not copy or summarize the full JSONL into the repo.
