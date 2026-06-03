# KV260 Event Camera Validation

Updated: 2026-06-02

This note documents the repeatable validation pass for the custom KV260 event camera GUI and recorder.

## Validation Command

Run from the repository root:

```sh
./scripts/kv260-validate-event-camera.py
```

The script validates:

- writer queue sanity and clean drain,
- installed launcher files,
- bias-control discovery,
- live preview with no recording,
- recording with `Recording Priority` on,
- playback-player open/render/stop behavior,
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
/tmp/kv260-event-camera-validation/20260602-034746/report.md
```

Overall result:

```text
PASS
```

Checks:

```text
writer_sanity: PASS
launcher_probe: PASS
bias_probe: PASS
live_preview_no_recording: PASS
recording_priority_on: PASS
playback_player: PASS
recording_priority_off: PASS
gui_smoke: skipped in this short rerun
```

## Key Results

Launcher probe:

```text
entries_ok=True
scripts_ok=True
executable_ok=True
```

Bias probe:

```text
device=/dev/v4l-subdev3
found=6
missing=[]
error=None
```

Writer queue sanity:

```text
accepted=16
file_size=65536
bytes_written=65536
queue_pending=0
drops=16
stop_elapsed_s=0.002
```

This confirms the writer drains cleanly and reports bounded-queue overflow instead of hiding it. The synthetic test intentionally enqueues more payloads than the small test queue accepts.

No-recording live preview:

```text
report=/tmp/kv260-event-camera-validation/20260602-194543/report.md
buffers=872
events=16520079
decoded_buffers=180
skipped_buffers=180
preview_errors=0
frames=46
changed_after_2s=37
active_event_frames_after_2s=37
active_event_max_after_2s=6171
```

This confirms the smooth preview path is still active when recording is off. The validator now checks real active event pixels after the first two seconds instead of only checking that GTK emitted frames. Preview intentionally decodes a bounded newest-payload stream instead of every captured payload, so skipped preview payloads are healthy when buffers, events, changed frames, and active event pixels continue advancing.

Recording with `Recording Priority` on:

```text
file_size=39262496
bytes_written=39262496
buffers_written=401
queue_pending=0
drops=0
write_error=None
stop_elapsed_s=0.004
decoded_buffers=80
skipped_buffers=184
active_event_frames_after_2s=21
replay_events_from_first_1MiB=105226
replay_nonblank=True
```

This confirms the default recording-first mode works as designed: recording wrote all accepted payload bytes, drained the queue, had zero raw drops, and reduced preview work during recording.

Playback player:

```text
events=40750
frames=7
nonblank_frames=7
observed_playback=True
stop_elapsed_s=0.277
```

This confirms the `Open Recording` code path can open a captured `.pse2.raw`, render nonblank playback frames, and stop cleanly.

Recording with `Recording Priority` off:

```text
file_size=27633760
bytes_written=27633760
buffers_written=399
queue_pending=0
drops=0
write_error=None
stop_elapsed_s=0.004
decoded_buffers=120
skipped_buffers=120
active_event_frames_after_2s=20
replay_events_from_first_1MiB=129624
replay_nonblank=True
```

This confirms the non-default toggle still preserves recording correctness. The current smooth-preview architecture remains bounded even with the toggle off; it does not return to the old “decode every payload” behavior because that was the source of the preview lag.

GUI lifecycle:

```text
display=:0
socket=True
return_code=0
```

The latest short rerun skipped the GUI lifecycle check because the live/recording paths were under test. The previous full pass confirmed the app opens on the local board display and exits cleanly through its command socket.

## Conclusion

The implementation is behaving correctly on the current KV260 image:

- Installed launcher files exist and their script targets are executable.
- Bias controls are discoverable on `/dev/v4l-subdev3`.
- Preview remains live when not recording, with intentional newest-payload decimation and active event pixels still present after the first two seconds.
- Recording keeps zero raw drops in the measured short runs while preview stays bounded.
- Recording priority off no longer restores full preview decoding because that older mode could make the preview fall behind.
- Recorded byte counts match actual file sizes.
- Writer queue drains to zero on stop.
- Recorded files replay through the custom EVT2.1 path and render nonblank frames.
- The playback-player path opens recordings and stops cleanly.
- The GUI starts and closes cleanly.

The current recorder remains the recommended capture path:

```text
.pse2.raw + .pse2.raw.json
```

Official Metavision RAW export should remain a separate converter step, not part of live capture.

## TDV Matrix

| Feature | Validation | Result | Notes |
| --- | --- | --- | --- |
| Desktop/menu launchers | `launcher_probe` | PASS | Verifies installed `.desktop` files and script executability. |
| Bias controls | `bias_probe` | PASS | Verifies six daily-use bias controls are readable. |
| Live preview | `live_preview_no_recording` | PASS | Decodes bounded latest samples while V4L2 buffers and events keep advancing. |
| Recording Priority on | `recording_priority_on` | PASS | Writes all queued bytes, zero drops, decimates preview. |
| Recording Priority off | `recording_priority_off` | PASS | Writes all queued bytes, zero drops, preview remains bounded. |
| Writer queue | `writer_sanity` | PASS | Verifies clean drain and explicit bounded-queue drop accounting. |
| Recording replay decode | recording replay sub-checks | PASS | First 1 MiB decodes into nonblank rendered frames. |
| Open Recording playback | `playback_player` | PASS | Starts playback, renders frames, stops cleanly. |
| GUI lifecycle | `gui_smoke` | previous PASS | GTK app starts on `:0` and exits through the command socket. |

## Improvement Candidates

These are the next reasonable improvements. None are required for the current recorder to work.

1. Add a playback speed control.
   The playback thread opens and renders correctly, but full-file replay can be slower than a quick validation timeout on larger files. A simple speed selector such as `Realtime`, `2x`, `5x`, and `Max` would make `Open Recording` more useful.

2. Add free-space warning before recording.
   Recording is currently robust at observed rates, but the GUI should warn when the target folder has low free space.

3. Add a small `Validate` button or menu item.
   The command-line TDV script works. A GUI button could run a shorter validation profile and open the latest report.

4. Add official RAW conversion as a separate tool.
   Keep live recording as `.pse2.raw + .json`; convert finished files later.

5. Consider a small C++ recorder helper only after measurement.
   Current Python path passes validation. C++ should only replace the raw capture/write path if CPU usage or bandwidth measurements prove Python is the bottleneck.
