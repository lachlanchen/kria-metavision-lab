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

Current hot-loop order:

```text
DQBUF
copy payload view
decode/draw preview
write recording
emit preview frame when due
QBUF
```

In the code, this currently happens in:

```text
scripts/kv260-event-camera-app.py
V4L2EventStream._run
```

## Most Important Simple Improvement

The best next improvement is not a complicated queue/thread redesign. It is just to return the V4L2 buffer to the driver as soon as the payload has been copied.

Recommended hot-loop order:

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

## What Not To Add Yet

Do not add these until there is measurement showing we need them:

- Separate writer thread.
- Bounded recording queue.
- Complicated recovery logic.
- Heavy loss-accounting UI.
- Official RAW export/conversion.
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

- Keep the current direct draw-and-decay renderer.
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

## Recommended Implementation Plan

When editing the recorder, make only this focused change first:

1. In `V4L2EventStream._run`, after `DQBUF`, copy the payload:

   ```python
   payload = bytes(self.buffers[buf.index][:buf.bytesused])
   ```

2. Immediately call:

   ```python
   fcntl.ioctl(self.fd, VIDIOC_QBUF, buf)
   ```

3. Then write `payload` if recording.

4. Then run `_decode_and_draw(payload)` for preview.

5. Remove the old final `QBUF` at the bottom of the loop so each buffer is queued exactly once.

6. Keep the rest of the GUI unchanged.

## Expected Result

After this small change:

- The app still records the same raw PSE2 bytes.
- The app still shows the same preview.
- The V4L2 buffer is returned to the driver earlier.
- Recording becomes less dependent on preview speed.
- The code stays understandable.

This is the best next step before considering any larger queue/thread design.

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
