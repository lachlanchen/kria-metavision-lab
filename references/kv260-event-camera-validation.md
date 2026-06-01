# KV260 Event Camera Validation

Updated: 2026-06-01

This note documents the repeatable validation pass for the custom KV260 event camera GUI and recorder.

## Validation Command

Run from the repository root:

```sh
./scripts/kv260-validate-event-camera.py
```

The script validates:

- writer queue sanity and clean drain,
- live preview with no recording,
- recording with `Recording Priority` on,
- recording with `Recording Priority` off,
- replay of the captured `.pse2.raw` files,
- GTK GUI lifecycle through the local command socket.

The script stops any existing custom/native viewer first so `/dev/video0` is not owned by another process.

Reports are written outside the repo by default:

```text
/tmp/kv260-event-camera-validation/YYYYMMDD-HHMMSS/report.json
/tmp/kv260-event-camera-validation/YYYYMMDD-HHMMSS/report.md
```

Recordings are written to:

```text
/home/petalinux/event_recordings
```

## Latest Deep Validation

Latest report:

```text
/tmp/kv260-event-camera-validation/20260601-065339/report.md
```

Overall result:

```text
PASS
```

Checks:

```text
writer_sanity: PASS
live_preview_no_recording: PASS
recording_priority_on: PASS
recording_priority_off: PASS
gui_smoke: PASS
```

## Key Results

Writer queue sanity:

```text
accepted=16
file_size=65536
bytes_written=65536
queue_pending=0
drops=16
```

This confirms the writer drains cleanly and reports bounded-queue overflow instead of hiding it. The synthetic test intentionally enqueues more payloads than the small test queue accepts.

No-recording live preview:

```text
buffers=187
decoded_buffers=187
skipped_buffers=0
preview_errors=0
frames=92
changed_after_2s=61
nonblank_frames=92
```

This confirms the smooth preview path is still active when recording is off: every captured payload was decoded for preview and no preview payloads were skipped.

Recording with `Recording Priority` on:

```text
file_size=11037336
bytes_written=11037336
buffers_written=120
queue_pending=0
drops=0
write_error=None
decoded_buffers=98
skipped_buffers=55
replay_events_from_first_1MiB=127046
replay_nonblank=True
```

This confirms the default recording-first mode works as designed: recording wrote all accepted payload bytes, drained the queue, had zero raw drops, and reduced preview work during recording.

Recording with `Recording Priority` off:

```text
file_size=5906328
bytes_written=5906328
buffers_written=195
queue_pending=0
drops=0
write_error=None
decoded_buffers=224
skipped_buffers=0
replay_events_from_first_1MiB=126290
replay_nonblank=True
```

This confirms the toggle works: recording still had zero drops, and preview decoded every captured payload after recorder enqueue.

GUI lifecycle:

```text
display=:0
socket=True
return_code=0
```

This confirms the app still opens on the local board display and exits cleanly through its command socket.

## Conclusion

The implementation is behaving correctly on the current KV260 image:

- Preview is smooth when not recording.
- Recording priority mode protects the recorder by reducing preview CPU work.
- Recording priority off restores full preview decoding for low-rate tests.
- Recorded byte counts match actual file sizes.
- Writer queue drains to zero on stop.
- Recorded files replay through the custom EVT2.1 path and render nonblank frames.
- The GUI starts and closes cleanly.

The current recorder remains the recommended capture path:

```text
.pse2.raw + .pse2.raw.json
```

Official Metavision RAW export should remain a separate converter step, not part of live capture.
