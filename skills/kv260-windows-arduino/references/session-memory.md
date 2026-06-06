# Session Memory And Cross-Agent Handoff

Use this reference when a task asks whether Codex can read conversation history, coordinate between the Windows Codex session and the KV260 Codex session, update `AGENTS.md`, or make the local skills know about each other.

## Capability

Codex session history is stored as local JSONL files. It can be read like any other file when filesystem permissions allow it.

Do not treat raw JSONL as durable project memory. It can contain passwords, tokens, account details, copied terminal transcripts, and stale instructions.

## Preferred Memory Order

1. Read the active `AGENTS.md`.
2. Use this skill.
3. Read repo references in `/home/petalinux/Projects/kria-kv260-starter/references`.
4. Fetch or inspect JSONL only when the user explicitly asks or when a specific missing fact cannot be recovered otherwise.
5. Write a short sanitized summary into `AGENTS.md`, a reference doc, or a skill reference.

## Private Board Cache

Raw Windows Codex session JSONL may be copied to the KV260 only under:

```text
/home/petalinux/Projects/kria-kv260-starter/private/windows-codex-history/
```

That directory is ignored by git. It is reciprocal to the Windows-side cache:

```text
C:\Users\Administrator\Projects\DualLampHI\private\kv260-codex-history\
```

Do not place raw JSONL in `references/`, `docs/`, `skills/`, or any tracked path.

Fetch the known Windows session:

```sh
/home/petalinux/.codex/skills/kv260-windows-arduino/scripts/fetch-windows-codex-session.sh \
  --session-id 019e6449-7a73-74d3-bd33-154399427cc5
```

List Windows sessions without copying:

```sh
/home/petalinux/.codex/skills/kv260-windows-arduino/scripts/fetch-windows-codex-session.sh --list
```

## Known Session Files

KV260 board session:

```text
/home/petalinux/.codex/sessions/2026/05/26/rollout-2026-05-26T07-14-26-019e64a3-0950-7491-8e3d-57f8541dd1b7.jsonl
```

Windows `polarizer` session:

```text
C:\Users\Administrator\.codex\sessions\2026\05\26\rollout-2026-05-26T20-36-37-019e6449-7a73-74d3-bd33-154399427cc5.jsonl
```

## Useful Commands

Find board session files:

```sh
find /home/petalinux/.codex/sessions -type f -name '*.jsonl' | sort
```

Find a Windows session by id from the KV260:

```sh
ssh -i /home/petalinux/.ssh/id_dropbear_rsa -y Administrator@192.168.1.166 \
  "cmd /c findstr /s /m /c:\"019e6449-7a73-74d3-bd33-154399427cc5\" C:\Users\Administrator\.codex\sessions\*.jsonl"
```

Inspect metadata without dumping a full transcript:

```sh
sed -n '1,3p' /home/petalinux/.codex/sessions/2026/05/26/rollout-2026-05-26T07-14-26-019e64a3-0950-7491-8e3d-57f8541dd1b7.jsonl
```

Search for a specific safe term:

```sh
rg -n "kv260-windows-arduino|kv260-arduino-event-control|Arduino CLI|COM3" \
  /home/petalinux/.codex/sessions \
  /home/petalinux/Projects/kria-kv260-starter/private/windows-codex-history
```

## What To Remember

- KV260 records event-camera data.
- Windows controls the Arduino over USB serial.
- Arduino has no IP address.
- KV260 recording API is `http://192.168.1.250:8765`.
- Future Windows Arduino API should be `http://192.168.1.166:8780`.
- Board skill: `/home/petalinux/.codex/skills/kv260-windows-arduino`.
- Windows skill: `C:\Users\Administrator\.codex\skills\kv260-arduino-event-control`.
- Versioned Windows skill source: `C:\Users\Administrator\Projects\DualLampHI\skills\kv260-arduino-event-control`.
- Windows mirrors board history under `C:\Users\Administrator\Projects\DualLampHI\private\kv260-codex-history`.
- KV260 mirrors Windows history under `/home/petalinux/Projects/kria-kv260-starter/private/windows-codex-history`.
