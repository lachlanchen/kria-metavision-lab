# Repository Guidelines

## Project Role
This KV260 repository is the board-side event-camera control environment for OpenHI / DualLampHI / V-SPICE experiments.

Current lab split:

- KV260 host `xilinx-kv260-starterkit-20222` at `192.168.1.250` records Prophesee event-camera data.
- Windows host `CSG1175-P` at `192.168.1.166` controls Arduino over USB serial.
- Arduino has no IP address. It is only reachable through the Windows COM port.
- KV260 recording API uses `http://192.168.1.250:8765`.
- Future Windows Arduino API, if implemented, should use `http://192.168.1.166:8780`.

## Cross-Session Memory
Use curated files as memory, not raw Codex session logs.

- KV260 skill: `/home/petalinux/.codex/skills/kv260-windows-arduino`
- KV260 skill doc: `references/kv260-windows-arduino-codex-skill.md`
- Windows peer skill: `C:\Users\Administrator\.codex\skills\kv260-arduino-event-control`
- Windows peer repo copy: `C:\Users\Administrator\Projects\DualLampHI\skills\kv260-arduino-event-control`
- Windows handoff docs live in `C:\Users\Administrator\Projects\DualLampHI\docs`

Do not ingest raw Codex history or SQLite logs wholesale. Prefer handoff docs, skills, helper scripts, and explicit user-approved files.

## Operating Rules
- KV260 owns the Prophesee event camera and `/dev/video0`.
- Only one process can own `/dev/video0`: GUI viewer, native viewer, or recording API.
- Use `takeover=true` when remote recording should stop viewers first.
- Windows should be the first controlled-experiment master because Arduino is physically attached to Windows.
- If KV260 must command Windows, target port `8780`, not the KV260 event API port `8765`.
- For robust synchronization, prefer an optical sync LED visible to the event camera.

## Common Commands

Start/check/stop API:

```sh
cd /home/petalinux/Projects/kria-kv260-starter
./scripts/kv260-event-camera-api.sh start
./scripts/kv260-event-camera-api.sh status
./scripts/kv260-event-camera-api.sh stop
```

Inspect lab status:

```sh
/home/petalinux/.codex/skills/kv260-windows-arduino/scripts/kv260-lab-status.sh
```

Probe Windows Arduino state:

```sh
/home/petalinux/.codex/skills/kv260-windows-arduino/scripts/windows-arduino-probe.sh
```

## Related Repos
- KV260 repo: `/home/petalinux/Projects/kria-kv260-starter` -> `git@github.com:lachlanchen/kria-metavision-lab.git`
- Windows DualLampHI: `C:\Users\Administrator\Projects\DualLampHI` -> `git@github.com:lachlanchen/DualLampHI.git`
- Windows V-SPICE: `C:\Users\Administrator\Projects\polarizer` -> `git@github.com:lachlanchen/V-SPICE.git`
- Windows OpenHI3.0: `C:\Users\Administrator\Projects\OpenHI3.0`
- Windows OpenHI2.0: `C:\Users\Administrator\Projects\OpenHI2.0`
