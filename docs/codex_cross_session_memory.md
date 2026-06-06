# Codex Cross-Session Memory: KV260 And Windows Arduino

Updated: 2026-06-06

This document mirrors the Windows-side `DualLampHI/docs/codex_cross_session_memory_cn.md` pattern for the KV260 side of the lab.

## What Can Be Read

The KV260 Codex session can reach the Windows host over SSH:

```sh
ssh -i /home/petalinux/.ssh/id_dropbear_rsa -y Administrator@192.168.1.166 "powershell -NoProfile -Command \"hostname\""
```

The Windows host has normal project files, local Codex skill files, helper scripts, and Codex state files under:

```text
C:\Users\Administrator\.codex
```

Known Windows Codex session file:

```text
C:\Users\Administrator\.codex\sessions\2026\05\26\rollout-2026-05-26T20-36-37-019e6449-7a73-74d3-bd33-154399427cc5.jsonl
```

## What Should Be Used As Memory

Use curated handoff and skill files as the source of truth:

```text
KV260:
  /home/petalinux/AGENTS.md
  /home/petalinux/Projects/kria-kv260-starter/AGENTS.md
  /home/petalinux/.codex/skills/kv260-windows-arduino
  /home/petalinux/Projects/kria-kv260-starter/skills/kv260-windows-arduino
  /home/petalinux/Projects/kria-kv260-starter/references/codex-session-cache-and-cross-memory.md
  /home/petalinux/Projects/kria-kv260-starter/references/kv260-windows-arduino-codex-skill.md

Windows:
  C:\Users\Administrator\Projects\DualLampHI\AGENTS.md
  C:\Users\Administrator\.codex\skills\kv260-arduino-event-control
  C:\Users\Administrator\Projects\DualLampHI\skills\kv260-arduino-event-control
  C:\Users\Administrator\Projects\DualLampHI\docs\codex_cross_session_memory_cn.md
  C:\Users\Administrator\Projects\DualLampHI\docs\kv260_arduino_connection_control_methods_cn.md
```

## What Should Not Be Used Automatically

Do not import raw Codex history or SQLite logs wholesale:

```text
/home/petalinux/.codex/history.jsonl
/home/petalinux/.codex/sessions/**/*.jsonl
/home/petalinux/.codex/logs_*.sqlite
/home/petalinux/.codex/memories_*.sqlite
C:\Users\Administrator\.codex\sessions\**\*.jsonl
```

These files can contain unrelated private context, stale reasoning, failed attempts, and credential-adjacent data. Read only specific files if the user explicitly names them or the task requires targeted recovery.

## Private Cache

When the KV260 needs Windows conversation context, fetch raw Windows JSONL only into:

```text
/home/petalinux/Projects/kria-kv260-starter/private/windows-codex-history/
```

This path is ignored by git.

This is reciprocal to the Windows-side private mirror:

```text
C:\Users\Administrator\Projects\DualLampHI\private\kv260-codex-history\
```

Fetch by session id:

```sh
/home/petalinux/.codex/skills/kv260-windows-arduino/scripts/fetch-windows-codex-session.sh \
  --session-id 019e6449-7a73-74d3-bd33-154399427cc5
```

List Windows sessions without copying:

```sh
/home/petalinux/.codex/skills/kv260-windows-arduino/scripts/fetch-windows-codex-session.sh --list
```

## Decision Rule Before Accessing Windows

When a KV260 Codex session needs to decide whether and how to access Windows:

1. Read curated Windows handoff docs first.
2. Read the Windows peer skill next.
3. Fetch Windows JSONL only for targeted recent context, such as a grep for `Arduino`, `COM3`, `arduino-cli`, `DualLampHI`, `polarizer`, `KV260`, `8765`, or `8780`.
4. Treat JSONL as conversation context, not ground truth.
5. Confirm with actual Windows files, Arduino CLI output, API status, process status, and device status before changing Windows or the board.

Useful targeted search after fetching:

```sh
rg -n "arduino|COM3|COM1|arduino-cli|recording API|DualLampHI|polarizer|8765|8780" \
  /home/petalinux/Projects/kria-kv260-starter/private/windows-codex-history
```

## Shared Operating Facts

```text
Windows host:
  hostname: CSG1175-P
  IP:       192.168.1.166
  role:     Arduino USB control and Windows-side repos

KV260 host:
  hostname: xilinx-kv260-starterkit-20222
  IP:       192.168.1.250
  role:     Prophesee event-camera recording
  API:      http://192.168.1.250:8765

Arduino:
  board:    Arduino UNO
  network:  none
  access:   Windows USB serial only
  sketch:   firmware/dual_led_direct_timer1/dual_led_direct_timer1.ino
```

## Peer Skills

KV260-side skill:

```text
name: kv260-windows-arduino
installed: /home/petalinux/.codex/skills/kv260-windows-arduino
versioned: /home/petalinux/Projects/kria-kv260-starter/skills/kv260-windows-arduino
role: tells KV260 Codex how to coordinate event recording and Windows Arduino control
```

Windows-side skill:

```text
name: kv260-arduino-event-control
installed: C:\Users\Administrator\.codex\skills\kv260-arduino-event-control
versioned: C:\Users\Administrator\Projects\DualLampHI\skills\kv260-arduino-event-control
role: tells Windows Codex how to coordinate Arduino control and KV260 recording
```

These two skills are peers. If one is updated with new IPs, ports, repo paths, scripts, serial protocols, or experiment workflow rules, update the other skill or its reference docs in the same change.

## Reciprocal Private Mirrors

Windows mirror of KV260 history:

```text
C:\Users\Administrator\Projects\DualLampHI\private\kv260-codex-history\kv260-history.jsonl
```

KV260 mirror of Windows history:

```text
/home/petalinux/Projects/kria-kv260-starter/private/windows-codex-history/rollout-2026-05-26T20-36-37-019e6449-7a73-74d3-bd33-154399427cc5.jsonl
```

Tracked summary docs:

```text
C:\Users\Administrator\Projects\DualLampHI\docs\kv260_private_history_mirror_summary_cn.md
/home/petalinux/Projects/kria-kv260-starter/references/windows-codex-private-history-mirror-summary.md
```
