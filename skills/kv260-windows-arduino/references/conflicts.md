# Conflicts And Failure Modes

Use this before changing ports, starting services, or debugging missing events.

## Arduino Is Not Network-Addressable

Arduino UNO is a USB serial device behind Windows. KV260 cannot talk to it directly.

Correct:

```text
KV260 -> Windows 192.168.1.166 -> Arduino COM port
```

## COM Port Not Confirmed

Windows handoff says Arduino was previously `COM3`, but current detection showed only `COM1 Unknown`.

Fix on Windows:

```powershell
arduino-cli board list
```

Do not design controlled experiments until the Arduino is visible again.

## API Port Confusion

Keep:

```text
KV260 event API:      192.168.1.250:8765
Windows Arduino API:  192.168.1.166:8780
```

Do not use `8765` for the Windows Arduino API unless there is a strong reason and all docs/scripts are updated.

## Windows Firewall

If KV260 calls the Windows Arduino API, Windows must allow inbound TCP `8780`.

If Windows orchestrates the whole experiment and calls KV260, this is usually not needed.

## `/dev/video0` Ownership

Only one owner at a time:

```text
custom KV260 Event Camera GUI
native metavision_viewer
headless recording API
```

Check:

```sh
fuser /dev/video0 2>/dev/null || true
cd /home/petalinux/Projects/kria-kv260-starter
./scripts/kv260-event-camera-switch.sh --status
```

Stop:

```sh
./scripts/kv260-event-camera-switch.sh --stop-all
```

## Phase Ambiguity

Autonomous Arduino LED modulation plus independent KV260 recording does not phase-lock start times.

Mitigations:

```text
infer phase from event pattern
reset Arduino near recording start
add optical sync LED visible to event camera
add electrical sync later if needed
```

## Recording Size

Event recordings can grow quickly. Keep them under:

```text
/home/petalinux/event_recordings
```

Move large runs to Windows when disk space becomes tight.
