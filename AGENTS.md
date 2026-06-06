# Repository Guidelines

This repository is the KV260-side workspace for the Prophesee event-camera lab.

## Operating Context

- Board: AMD/Xilinx Kria KV260 running PetaLinux.
- Event camera: Prophesee sensor exposed through V4L2, normally `/dev/video0`.
- Local board host: `xilinx-kv260-starterkit-20222`, currently `192.168.1.250`.
- Paired Windows host: `CSG1175-P`, currently `192.168.1.166`.
- Windows owns the USB Arduino serial port for light-control experiments.

Run board commands directly. Do not SSH back into this KV260 from a board-side Codex session.

## Project Structure

- `scripts/` contains the custom viewer, recording API, launchers, desktop setup, recovery tools, and Windows helper scripts.
- `references/` contains durable research notes and setup records.
- `docs/assets/` contains README screenshots.
- `SystemMaintenance/` contains board maintenance scripts.
- `i18n/` contains multilingual README pages.

Keep generated event data out of the repo. Default recordings belong in `/home/petalinux/event_recordings`.

## Common Commands

Start or check the headless recording API:

```sh
cd /home/petalinux/Projects/kria-kv260-starter
./scripts/kv260-event-camera-api.sh start
./scripts/kv260-event-camera-api.sh status
```

Open, route, or stop viewers:

```sh
./scripts/kv260-event-camera-switch.sh --board
./scripts/kv260-event-camera-switch.sh --windows
./scripts/kv260-event-camera-switch.sh --stop-all
```

Inspect the Windows/Arduino/KV260 lab state:

```sh
/home/petalinux/.codex/skills/kv260-windows-arduino/scripts/kv260-lab-status.sh
/home/petalinux/.codex/skills/kv260-windows-arduino/scripts/windows-arduino-probe.sh
```

## Skills And Cross-Session Memory

Use the local KV260 skill for Arduino/light-control coordination:

```text
/home/petalinux/.codex/skills/kv260-windows-arduino/SKILL.md
```

Versioned source for that skill lives in this repo:

```text
skills/kv260-windows-arduino
```

The paired Windows skill is:

```text
C:\Users\Administrator\.codex\skills\kv260-arduino-event-control\SKILL.md
```

Do not paste raw Codex JSONL into repo docs. If session history is needed, inspect it only by explicit user request and write a sanitized operational summary.

This repo mirrors the Windows `DualLampHI` memory layout:

```text
docs/codex_cross_session_memory.md
skills/kv260-windows-arduino/
references/codex-session-cache-and-cross-memory.md
```

Windows Codex sessions can be fetched to the private board cache:

```text
private/windows-codex-history/
```

This mirrors the Windows-side reciprocal cache:

```text
C:\Users\Administrator\Projects\DualLampHI\private\kv260-codex-history\
```

Both `private/` and `.codex-session-cache/` are ignored by git. Use the skill helper rather than manually copying JSONL into tracked folders:

```sh
/home/petalinux/.codex/skills/kv260-windows-arduino/scripts/fetch-windows-codex-session.sh --session-id 019e6449-7a73-74d3-bd33-154399427cc5
```

Known JSONL locations:

```text
Board:
/home/petalinux/.codex/sessions/2026/05/26/rollout-2026-05-26T07-14-26-019e64a3-0950-7491-8e3d-57f8541dd1b7.jsonl

Windows:
C:\Users\Administrator\.codex\sessions\2026\05\26\rollout-2026-05-26T20-36-37-019e6449-7a73-74d3-bd33-154399427cc5.jsonl
```

## Coordination Rules

- KV260 records events.
- Windows controls Arduino over USB serial.
- Arduino has no IP address.
- KV260 event API uses port `8765`.
- Future Windows Arduino API should use port `8780`.
- Only one owner can hold `/dev/video0`.
- Use `takeover=true` for remote recording when stale viewers may exist.
- Keep official/raw conversion separate from the live recorder unless a task explicitly changes that design.

## Git Discipline

Commit and push after repo edits unless the user explicitly says not to.

Before committing public-facing docs, avoid adding passwords, tokens, private account credentials, or raw transcript contents.

## Codex History JSONL Decision Rule

The board-side Codex conversation history path is:

```text
/home/petalinux/.codex/history.jsonl
```

Use it only for targeted recent context when deciding what happened on the board. Prefer curated docs and skills first:

1. `references/windows-arduino-codex-handoff.md`
2. `references/kv260-windows-arduino-codex-skill.md`
3. `/home/petalinux/.codex/skills/kv260-windows-arduino/SKILL.md`
4. targeted `tail` or `grep` from `/home/petalinux/.codex/history.jsonl`

Do not import full JSONL history, SQLite logs, auth files, or memory databases as canonical project state. Verify important claims against real files, scripts, process state, and devices.
