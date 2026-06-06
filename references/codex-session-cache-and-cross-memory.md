# Codex Session Cache And Cross-Memory

Updated: 2026-06-06

This note documents how the KV260 Codex session can fetch Windows Codex session history for targeted recovery while keeping raw conversation logs out of git.

It mirrors the Windows-side operation documented in:

```text
/home/petalinux/Projects/DualLampHI/docs/codex_cross_session_memory_cn.md
C:\Users\Administrator\Projects\DualLampHI\docs\codex_cross_session_memory_cn.md
```

Reciprocal cache layout:

```text
Windows stores board history:
  C:\Users\Administrator\Projects\DualLampHI\private\kv260-codex-history\

KV260 stores Windows history:
  /home/petalinux/Projects/kria-kv260-starter/private/windows-codex-history/
```

Mirrored KV260-side tracked structure:

```text
docs/codex_cross_session_memory.md
skills/kv260-windows-arduino/
references/codex-session-cache-and-cross-memory.md
references/windows-codex-private-history-mirror-summary.md
```

## Purpose

The lab has two active Codex environments:

```text
KV260 board:
  /home/petalinux
  /home/petalinux/Projects/kria-kv260-starter

Windows host:
  C:\Users\Administrator
  C:\Users\Administrator\Projects\polarizer
  C:\Users\Administrator\Projects\DualLampHI
```

When a task crosses the Windows/KV260 boundary, the board session may need to understand what the Windows session already did, such as Arduino CLI setup, USB serial detection, repo updates, or Windows shortcut/API plans.

Raw Codex JSONL can be useful for targeted recovery, but it is not safe as durable project memory.

## Private Cache

Use this ignored board-side cache for copied Windows session logs:

```text
/home/petalinux/Projects/kria-kv260-starter/private/windows-codex-history/
```

The repo `.gitignore` includes:

```text
private/
```

Do not put raw session JSONL in these tracked locations:

```text
references/
docs/
skills/
AGENTS.md
README.md
```

Only sanitized conclusions should be committed.

## Fetch Helper

Installed helper:

```text
/home/petalinux/.codex/skills/kv260-windows-arduino/scripts/fetch-windows-codex-session.sh
```

Versioned source:

```text
/home/petalinux/Projects/kria-kv260-starter/skills/kv260-windows-arduino/scripts/fetch-windows-codex-session.sh
```

Fetch by known session id:

```sh
/home/petalinux/.codex/skills/kv260-windows-arduino/scripts/fetch-windows-codex-session.sh \
  --session-id 019e6449-7a73-74d3-bd33-154399427cc5
```

List Windows Codex sessions without copying:

```sh
/home/petalinux/.codex/skills/kv260-windows-arduino/scripts/fetch-windows-codex-session.sh --list
```

Fetch by explicit Windows path:

```sh
/home/petalinux/.codex/skills/kv260-windows-arduino/scripts/fetch-windows-codex-session.sh \
  --remote-path C:/Users/Administrator/.codex/sessions/2026/05/26/rollout-2026-05-26T20-36-37-019e6449-7a73-74d3-bd33-154399427cc5.jsonl
```

## Known Session Paths

Board session:

```text
/home/petalinux/.codex/sessions/2026/05/26/rollout-2026-05-26T07-14-26-019e64a3-0950-7491-8e3d-57f8541dd1b7.jsonl
```

Windows session:

```text
C:\Users\Administrator\.codex\sessions\2026\05\26\rollout-2026-05-26T20-36-37-019e6449-7a73-74d3-bd33-154399427cc5.jsonl
```

## Safe Use Pattern

1. Read `AGENTS.md` first.
2. Read the relevant skill.
3. Read versioned docs in `references/`.
4. Fetch JSONL only when the needed fact is still missing.
5. Search for targeted terms instead of reading the full transcript.
6. Commit only sanitized summaries or operational rules.

Useful targeted searches:

```sh
rg -n "Arduino|COM3|COM1|arduino-cli|KV260|recording API|8765|8780|DualLampHI|polarizer" \
  /home/petalinux/Projects/kria-kv260-starter/private/windows-codex-history
```

## What Future Agents Should Learn From The Cache

Use the fetched Windows history to answer narrow questions such as:

```text
What did the Windows session install or configure?
Which Windows repo contains the Arduino code?
Which COM port was detected?
What API or serial protocol was proposed?
Which commit introduced a Windows-side skill or handoff note?
```

Do not use raw history as authority for current hardware state. Re-check live state with:

```sh
/home/petalinux/.codex/skills/kv260-windows-arduino/scripts/kv260-lab-status.sh
/home/petalinux/.codex/skills/kv260-windows-arduino/scripts/windows-arduino-probe.sh
```

## Current Durable Memory

Board local memory:

```text
/home/petalinux/AGENTS.md
```

KV260 repo memory:

```text
/home/petalinux/Projects/kria-kv260-starter/AGENTS.md
```

KV260 skill:

```text
/home/petalinux/.codex/skills/kv260-windows-arduino
```

Windows peer skill:

```text
C:\Users\Administrator\.codex\skills\kv260-arduino-event-control
```

## Reciprocal Summary Docs

Windows summary of board history mirror:

```text
C:\Users\Administrator\Projects\DualLampHI\docs\kv260_private_history_mirror_summary_cn.md
/home/petalinux/Projects/DualLampHI/docs/kv260_private_history_mirror_summary_cn.md
```

KV260 summary of Windows history mirror:

```text
/home/petalinux/Projects/kria-kv260-starter/references/windows-codex-private-history-mirror-summary.md
```
