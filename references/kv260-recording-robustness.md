# KV260 Event Recording Robustness

Updated: 2026-06-01

This note records the current design judgment for recording Prophesee event data in the custom KV260 GUI. The goal is robustness and correctness first, then ease of use and smooth preview. The design should stay simple unless measurements show a real bottleneck.

## Current Recorder Status

The custom GUI records from the board's V4L2 event node:

```text
/dev/video0
Driver: psee-dma
Pixel format: PSE2 / EVT2.1
```

The current recording file is:

```text
event_YYYYMMDD_HHMMSS.pse2.raw
```

The file is the raw PSE2/EVT2.1 payload bytes dequeued from V4L2, plus a JSON sidecar. It is efficient because it does not store rendered preview frames and does not re-encode events.

Current conclusion:

- Efficient: yes.
- Correct for buffers successfully dequeued from V4L2: yes.
- Official Metavision RAW container: no.
- Strictly proven lossless: not yet.
- Good enough for normal low/medium rate board-side recordings: likely yes.

The important limitation is that the current loop still gives preview work time inside the same capture loop.

Old hot-loop order before the 2026-06-01 robustness patch:

```text
DQBUF
copy payload view
decode/draw preview
write recording
emit preview frame when due
QBUF
```

The old behavior was in:

```text
scripts/kv260-event-camera-app.py
V4L2EventStream._run
```

Current hot-loop order after the first robustness patch:

```text
DQBUF
copy payload bytes
QBUF immediately
write recording bytes
decode/draw preview
emit preview frame when due
```

Current hot-loop order after the bounded-writer patch:

```text
DQBUF
copy payload bytes
QBUF immediately
enqueue copied bytes into bounded recording queue if recording
decode/draw preview
emit preview frame when due
```

Current hot-loop order after the recording-preview decimation patch:

```text
DQBUF
copy payload bytes
QBUF immediately
enqueue copied bytes into bounded recording queue if recording
if not recording: decode/draw every payload
if recording: decode/draw only when a preview frame is due
emit preview frame when due
```

## Most Important Simple Improvement

The best first improvement was not a complicated queue/thread redesign. It was just to return the V4L2 buffer to the driver as soon as the payload was copied.

Implemented hot-loop order:

```text
DQBUF
copy payload bytes
QBUF immediately
write recording bytes
decode/draw preview only after the buffer is returned
```

This keeps the V4L2 buffer ownership time short. Preview work can still happen, but it no longer delays `QBUF`.

This is the smallest change that clearly improves recording robustness without making the application harder to reason about.

## Why This Is The Right First Step

V4L2 streaming works by exchanging queued buffers between the driver and userspace. After `VIDIOC_DQBUF`, the application owns that buffer. After `VIDIOC_QBUF`, the driver can reuse it. Holding a dequeued buffer longer than needed reduces the number of free driver buffers.

For mmap V4L2 capture, the payload must be copied before `QBUF`, because the mmap buffer can be reused by the driver after it is requeued.

The desired sequence is therefore:

```python
payload = bytes(self.buffers[buf.index][:buf.bytesused])
fcntl.ioctl(self.fd, VIDIOC_QBUF, buf)
```

Then recording and preview can use the copied `payload`.

## What Not To Add Until Measured

The first pass intentionally avoided architectural churn. Stage 2 later added the one background writer that directly supports recording robustness. Do not add more machinery until measurement shows we need it:

- Complicated recovery logic.
- Heavy loss-accounting UI.
- Official RAW export/conversion in the live recorder.
- Multiple writer stages.
- Large architectural split between capture, recording, and preview.

These can be useful later, but they are not the first change. They add complexity and may not improve performance on this KV260 image.

## Minimal Error Checks Worth Considering

If we want a small amount of confidence without making the design complex, these are the only checks worth adding with the hot-loop reorder:

- Count total V4L2 buffers captured.
- Count total bytes written.
- Record any disk write exception.
- Optionally record V4L2 `sequence` gaps if this driver increments `buf.sequence` meaningfully.
- Optionally record V4L2 buffer error flags if they appear.

No recovery behavior is needed at first. The recorder can just write the numbers into the JSON sidecar and show a short status line.

## Preview Priority

For recording, preview is not important. Preview should never make recording worse.

Simple preview policy:

- Keep the current bounded recent-event preview renderer.
- During recording, decode preview after the raw payload has already been copied, queued back to the driver, and written.
- If needed later, decode preview only when a preview frame is due.

This keeps the app easy to use while making the recording path more important than visualization.

## Metavision And OpenEB Lessons

The Metavision sample recorder starts raw logging at the stream facility level with:

```python
device.get_i_events_stream().log_raw_data(log_path)
```

Then it runs display logic separately through the event iterator and frame generator. The important idea is that recording is based on the raw event stream, not on preview frames.

OpenEB's `I_EventsStream` documentation says raw logging writes buffers when raw data is pulled through the stream API. OpenEB's `RAWEventFileLogger` also buffers raw data and only sends larger chunks to the writer path.

The lesson for our app is not "copy the whole SDK architecture." The practical lesson is simpler:

- Record raw bytes.
- Keep recording close to the capture path.
- Keep preview secondary.
- Batch writes enough to avoid tiny disk writes.

Our current Python file object already uses a 1 MiB buffer. That is reasonable for the current app.

## Implemented Change

Implemented in:

```text
scripts/kv260-event-camera-app.py
V4L2EventStream._run
```

The implementation now does this after `DQBUF`:

```python
payload = bytes(self.buffers[buf.index][:buf.bytesused])
fcntl.ioctl(self.fd, VIDIOC_QBUF, buf)
```

Then it writes `payload` to the recording file if recording is active. Preview decoding happens after the recording write.

Preview decode exceptions are counted and reported, but they no longer stop recording. This keeps recording more important than visualization.

## Verification

Static checks:

```text
python3 -m py_compile scripts/kv260-event-camera-app.py
git diff --check
```

Live preview smoke test after the patch:

```text
LIVE_RESULT frames=91 diffs=90 after_2s_frames=59 after_2s_diffs=59 events=476713 buffers=175 preview_errors=0
```

Recording smoke test after the patch:

```text
REC_RESULT path=/home/petalinux/event_recordings/recording_hotloop_test_20260601_061553.pse2.raw
file_size=3350960
recorded_bytes=3350960
record_events=400690
total_events=545652
total_buffers=205
frames=105
diffs=104
preview_errors=0
```

Replay smoke test on that recording:

```text
REPLAY_RESULT decoded_events=65345 preview_events=65345 nonblank=True
```

GUI smoke test:

```text
GUI_SMOKE rc=0
```

## Expected Result

After this small change:

- The app still records the same raw PSE2 bytes.
- The app still shows the same preview.
- The V4L2 buffer is returned to the driver earlier.
- Recording becomes less dependent on preview speed.
- The code stays understandable.

This remains the right stopping point before considering any larger queue/thread design. If future tests show recording still suffers under high event rate, then the next step should be measured rather than assumed.

## Stage 2 Bounded Writer

Stage 2 adds a bounded asynchronous raw writer. This is still a simple recording-first design, not an error-correction system.

Implemented hot path:

```text
DQBUF
copy payload bytes
QBUF immediately
enqueue copied bytes into bounded recording queue if recording
decode/draw preview after recording enqueue
```

Writer path:

```text
writer thread drains recording queue
writer thread writes raw payload bytes to disk
stop recording waits for queued payloads to flush
JSON sidecar stores final byte/buffer/drop counters
```

This gives the recorder a small RAM cushion for short disk stalls. If sustained event bandwidth exceeds storage bandwidth, no userspace design can guarantee saving everything forever. In that case the bounded queue may overflow and the app counts dropped recording payloads rather than trying complex recovery.

Important philosophy:

- Recording is more important than preview.
- Preview may lag or be reduced during recording.
- Preview should be smooth when not recording.
- Use buffers to absorb short bursts.
- Do not add infinite recovery, retry loops, or complicated error correction.
- C++ is acceptable later if Python becomes the measured bottleneck, but the first implementation should keep the GUI workflow intact.

The current default queue size is:

```text
KV260_RECORD_QUEUE_BUFFERS=256
```

The C++ path, if needed later, should be a small V4L2 raw recorder helper that owns capture and writing. It should not be a full GUI rewrite.

## Stage 2 Verification

Writer-only queue/drop path:

```text
WRITER_RESULT accepted=8 size=836 expected=836 stats_bytes=836 buffers=8 drops=7 pending=0 error=None status=stopped
```

Live preview after bounded writer:

```text
LIVE_RESULT frames=98 diffs=97 after_2s_frames=66 after_2s_diffs=66 events=403704 buffers=191 preview_errors=0
```

Default queue recording test:

```text
REC_RESULT path=/home/petalinux/event_recordings/recording_queue_test_20260601_062454.pse2.raw
file_size=3990184
stats_bytes=3990184
buffers_written=326
queued_buffers=326
drops=0
pending=0
error=None
record_events=512502
total_events=655847
total_buffers=345
frames=176
diffs=175
preview_errors=0
```

Replay smoke test on the default queue recording:

```text
REPLAY_RESULT decoded_events=131745 preview_events=131745 nonblank=True
```

Small queue recording test with `KV260_RECORD_QUEUE_BUFFERS=8`:

```text
QUEUE8_RESULT path=/home/petalinux/event_recordings/recording_queue8_test_20260601_062519.pse2.raw
file_size=2379888
stats_bytes=2379888
buffers_written=231
queued=231
drops=0
pending=0
error=None
preview_errors=0
```

GUI lifecycle smoke test:

```text
GUI_SMOKE rc=0
```

The default and small-queue camera tests both had zero recording drops at the observed event rates. The writer-only test intentionally used a tiny queue and a fast enqueue burst to prove the bounded drop accounting path works.

## Stage 3 Recording Preview Decimation

Stage 3 kept preview smooth when not recording and reduced preview CPU cost while recording. It has since been superseded by the June 2026 smooth-preview architecture below.

Policy:

- Not recording: decode every payload for the live preview. This was later changed because it was too expensive at higher event rates.
- Recording: enqueue every copied raw payload into the recorder, but only decode preview payloads when a display frame is due.
- Recording remains prioritized over visualization.

Verification after the patch:

```text
LIVE_RESULT frames=84 diffs=83 after_2s_frames=54 after_2s_diffs=54 events=673922 buffers=174 decoded_buffers=174 skipped_buffers=0 preview_errors=0
```

Recording test:

```text
REC_RESULT path=/home/petalinux/event_recordings/recording_decimated_preview_test_20260601_063547.pse2.raw
file_size=13695824
stats_bytes=13695824
buffers_written=154
queued_buffers=154
drops=0
pending=0
error=None
total_events=1823797
total_buffers=169
decoded_buffers=99
skipped_buffers=70
frames=94
diffs=93
preview_errors=0
```

Replay smoke test:

```text
REPLAY_RESULT decoded_events=127776 preview_events=127776 nonblank=True
```

GUI lifecycle smoke test:

```text
GUI_SMOKE rc=0
```

## Stage 4 GUI Status And Recording Priority

Stage 4 exposes the current recording state in the GUI and makes the recording-first preview policy explicit.

The camera tab now shows a compact status line:

```text
Recording: 12.4 MB, 912 buffers, queue 0/256, drops 0
```

The status is intentionally small. It reports the values that matter during daily use:

- bytes already written by the writer thread,
- buffers written,
- pending writer queue depth,
- queue capacity,
- dropped raw payload count,
- preview payloads skipped when recording priority is active.

The camera tab also has a default-on `Recording Priority` toggle.

When `Recording Priority` is on:

- every copied raw payload is still offered to the recorder,
- preview is decoded only when a display frame is due,
- live preview does less CPU work while recording,
- stop waits for the writer queue to drain cleanly.

When `Recording Priority` is off:

- every copied raw payload is still offered to the recorder first,
- preview remains bounded by the current live preview cadence,
- this avoids returning to the old full-preview decode path that could make the app fall behind.

The default stays on because recording correctness is more important than preview smoothness while actively saving data.

Verification after the patch:

```text
LIVE_RESULT frames=61 diffs=60 after_frames=31 after_diffs=30 events=882114 buffers=125 decoded_buffers=125 skipped_buffers=0 preview_errors=0 priority=True
```

Recording priority on:

```text
REC_ON_RESULT file_size=9881880 stats_bytes=9881880 stats_buffers=118 stats_drops=0 stats_pending=0 stats_error=None decoded_buffers=82 skipped_buffers=55 preview_errors=0 replay_events=63346 replay_nonblank=True priority=True
```

Recording priority off:

```text
REC_OFF_RESULT file_size=4965648 stats_bytes=4965648 stats_buffers=172 stats_drops=0 stats_pending=0 stats_error=None decoded_buffers=207 skipped_buffers=0 preview_errors=0 replay_events=68751 replay_nonblank=True priority=False
```

GUI lifecycle smoke test:

```text
GUI_SMOKE rc=0
```

## Stage 5 Smooth Preview Worker

Stage 5 mirrors the native Metavision viewer architecture more closely. Native OpenEB feeds camera callbacks into `CDFrameGenerator`, then displays generated frames from a separate loop. The custom GTK app now follows the same separation while staying on the direct V4L2 path:

- the capture thread dequeues, copies, requeues, records, and counts events,
- a bounded preview queue receives payload copies after the recorder enqueue,
- the preview worker drains stale queued payloads and processes only the newest few,
- the preview worker updates a recent-event time surface using EVT2.1 CD event types `0` and `1`,
- the display worker renders active pixels from that surface for the live accumulation window,
- old preview payloads are dropped by design so capture and recording do not wait for GTK.

Measured defaults:

```text
KV260_EVENT_MAX_LIVE_DISPLAY_FPS=24
KV260_EVENT_MAX_LIVE_DRAW_FPS=20
KV260_EVENT_PREVIEW_QUEUE_BUFFERS=8
KV260_EVENT_PREVIEW_PAYLOADS_PER_FRAME=4
KV260_EVENT_PREVIEW_RECORDING_PAYLOADS_PER_FRAME=2
KV260_EVENT_PREVIEW_CD_WORDS=4096
KV260_EVENT_LIVE_MIN_ACCUMULATION_US=200000
KV260_EVENT_LIVE_MIN_POINT_RADIUS=1
Point radius control default=0
```

Validation after the patch:

```text
report: /tmp/kv260-event-camera-validation/20260602-200709/report.md
live_preview_no_recording: buffers=1800 events=24062663 decoded=332 skipped=332 preview_errors=0 frames=84 changed_after_10s=37 active_after_10s=37 active_max_after_10s=79068
recording_priority_on: file_size=21832336 bytes_written=21832336 buffers=400 drops=0 pending=0 write_error=None decoded=80 skipped=192 active_after=23
recording_priority_off: file_size=19113608 bytes_written=19113608 buffers=400 drops=0 pending=0 write_error=None decoded=116 skipped=116 active_after=19
```

The important pass condition is no preview errors, advancing frames, active event pixels still present after ten seconds in the long live test, and zero recording drops. `skipped` preview payloads are expected and healthy in this design because preview intentionally drops stale payloads instead of letting GTK delay capture or recording.

## Separate Converter Direction

The live recorder should keep writing:

```text
.pse2.raw + .pse2.raw.json
```

This is the stable capture format for this project. It is simple, fast, and close to the V4L2 payload stream.

Official Metavision RAW compatibility should be added as a separate converter later:

```text
.pse2.raw -> official-ish Metavision RAW
```

That converter should read our raw payload and JSON metadata after recording has finished. It should not sit in the live capture path. Keeping conversion separate avoids risking the stable recorder.

## C++ Helper Direction

Only consider C++ if Python becomes a measured bottleneck.

The C++ target should be small:

```text
kv260-raw-recorder-helper
```

Its job should be only:

```text
V4L2 capture -> raw file writing -> compact stats
```

It should not implement the GTK GUI. The GUI can start/stop the helper and display the helper stats. This keeps the GUI easy to maintain while giving the recording path a lower-overhead option if measurements prove it is needed.

## References

- Linux V4L2 buffer structure and buffer queueing:
  - `https://www.kernel.org/doc/html/v4.8/media/uapi/v4l/buffer.html`
  - `https://www.kernel.org/doc/html/v4.12/media/uapi/v4l/vidioc-qbuf.html`
- Prophesee/Metavision recording guide:
  - `https://docs.prophesee.ai/stable/guides/events_recording.html`
- Prophesee RAW file format guide:
  - `https://docs.prophesee.ai/stable/data/file_formats/raw.html`
- Local OpenEB references:
  - `/home/petalinux/Projects/openeb/hal/cpp/include/metavision/hal/facilities/i_events_stream.h`
  - `/home/petalinux/Projects/openeb/sdk/modules/core/python/samples/metavision_simple_recorder/metavision_simple_recorder.py`
  - `/home/petalinux/Projects/openeb/sdk/modules/stream/cpp/src/raw_event_file_logger.cpp`
