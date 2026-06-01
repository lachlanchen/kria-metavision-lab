# KV260 OpenEB Custom Viewer Research

Updated: 2026-05-31

This note records the research behind the custom KV260 event-camera viewer improvements.

## Current Board Reality

The KV260 image includes Metavision command-line tools and shared libraries:

```text
/usr/bin/metavision_viewer
/usr/bin/metavision_file_info
/usr/lib/libmetavision_hal.so.5
/usr/lib/libmetavision_sdk_core.so.5
/usr/lib/libmetavision_sdk_stream.so.5
/usr/lib/libmetavision_sdk_ui.so.5
```

The installed Metavision runtime reports:

```text
metavision_software_info --version -> 5.0.0
```

The Python bindings are not installed in the current board Python environment:

```text
metavision_core
metavision_sdk_core
metavision_sdk_ui
metavision_hal
metavision_sdk_cv
```

That means the custom Python GTK viewer should not depend on `EventsIterator` or `PeriodicFrameGenerationAlgorithm` at runtime on this board. It can still mirror the SDK design using local decoding and accumulation.

## OpenEB References Used

Local OpenEB clone:

```text
/home/petalinux/Projects/openeb
tag: 5.2.0
commit: 9003b54
```

Useful source files:

```text
/home/petalinux/Projects/openeb/sdk/modules/stream/cpp/samples/metavision_viewer/metavision_viewer.cpp
/home/petalinux/Projects/openeb/sdk/modules/core/python/samples/metavision_simple_viewer/metavision_simple_viewer.py
/home/petalinux/Projects/openeb/sdk/modules/core/python/samples/metavision_filtering/metavision_filtering.py
/home/petalinux/Projects/openeb/hal/cpp/include/metavision/hal/decoders/evt21/evt21_event_types.h
/home/petalinux/Projects/openeb/hal/cpp/include/metavision/hal/decoders/evt21/evt21_decoder.h
/home/petalinux/Projects/openeb/hal/cpp/include/metavision/hal/facilities/i_ll_biases.h
```

Important OpenEB design points copied into the custom app:

- EVT2.1/PSE2 events are 64-bit vector events.
- CD event types are polarity-specific and carry a 32-bit valid mask for neighboring x positions.
- `EVT_TIME_HIGH` words carry the high timestamp bits; CD words carry the low 6 timestamp bits.
- The native viewer uses a 10 ms display accumulation window and a 30 FPS display loop.
- The SDK Python examples use `PeriodicFrameGenerationAlgorithm(..., accumulation_time_us=10000)` with a dark palette.

## Official Documentation Used

- Prophesee Biases manual: `https://docs.prophesee.ai/stable/hw/manuals/biases.html`
- Prophesee Event Signal Processing manual: `https://docs.prophesee.ai/stable/hw/manuals/esp.html`
- Prophesee frame generation guide: `https://docs.prophesee.ai/stable/guides/frames_generators.html`
- Prophesee event file opening guide: `https://docs.prophesee.ai/stable/guides/event_file_opening.html`

Key takeaways:

- The generally useful biases are `bias_diff_on`, `bias_diff_off`, `bias_fo`, `bias_hpf`, and `bias_refr`.
- `bias_diff_on` and `bias_diff_off` tune ON/OFF contrast thresholds.
- `bias_fo` and `bias_hpf` tune low-pass/high-pass bandwidth behavior.
- `bias_refr` tunes refractory time and should be treated as advanced.
- ESP features such as AFK, STC/Trail, ERC, and event-rate activity filtering exist in the SDK/HAL, but this board currently exposes only the sensor bias controls through V4L2.
- Metavision event files can be RAW, DAT, or HDF5. The current custom recordings are raw V4L2 PSE2 payload dumps, not full Metavision RAW containers.

## Board Controls Found

The event stream is:

```text
/dev/video0
Driver: psee-dma
Format: PSE2, 64-bit Prophesee EVT2.1
Geometry: 1280x720
```

The sensor subdevice is:

```text
/dev/v4l-subdev3
Entity: imx636 6-003c
```

The useful V4L2 bias controls are:

| Control | Range | Default | Daily-use role |
| --- | ---: | ---: | --- |
| `bias_diff_on` | `15..255` | `104` | ON event contrast threshold |
| `bias_diff_off` | `15..255` | `55` | OFF event contrast threshold |
| `bias_hpf` | `0..150` | `0` | Suppress slow background changes |
| `bias_fo` | `45..140` | `86` | Low-pass bandwidth and flicker/noise tuning |
| `bias_refr` | `0..255` | `20` | Advanced burst/refractory tuning |
| `bias_diff` | `52..100` | `77` | Expert reference contrast bias |

These are absolute V4L2 driver values on this board. The official IMX636 SDK documentation describes API bias values as relative offsets around default. The app therefore reads live V4L2 ranges instead of hard-coding documentation ranges.

## Implementation Decision

The custom viewer keeps the direct V4L2 capture path because it is the most reliable path on this PetaLinux image. The implementation deliberately separates live display from recording playback:

- Live camera preview uses the original immediate draw-and-decay path. Every V4L2 payload is decoded, painted directly into the preview canvas, then faded between frames. This matched the old working viewer and stayed live in the 5-second regression test.
- Recording playback uses the OpenEB-inspired timestamp accumulation path. This is where the 10 ms accumulation window is useful, because the event timestamps are available in controlled file chunks.

A previous attempt to use the timestamp accumulator for live V4L2 streaming caused the app to show an initial burst of events and then gradually fade/static on the board. The current code therefore avoids the timestamp renderer in the live hot path.

It implements the OpenEB-style parts that matter for daily use:

- Timestamp-aware EVT2.1 decoding.
- 10 ms default display accumulation for playback.
- 30 FPS default rendering.
- Dark/light/gray/cool-warm palettes.
- ON/OFF/all polarity filtering.
- Optional event trail persistence.
- Raw PSE2 recording and playback.
- Bias refresh/apply/reset/save/load through V4L2.

The app intentionally does not expose every SDK/HAL facility yet. ERC, AFK, and STC/Trail should be added later only if we add an OpenEB HAL helper or confirm equivalent controls are exposed by this board image.

## Recording Format Notes

Custom recordings use:

```text
event_YYYYMMDD_HHMMSS.pse2.raw
event_YYYYMMDD_HHMMSS.pse2.raw.json
```

The `.raw` file is the exact V4L2 PSE2/EVT2.1 byte stream from `/dev/video0`. The custom app can replay this format directly.

The files are not guaranteed to be official Metavision RAW containers. `metavision_file_info` may reject them because they do not carry a Metavision RAW header and plugin metadata.

For responsiveness, playback uses compressed preview timing for large raw chunks. The goal is to inspect the recording visually inside the custom GUI, not to provide scientific timestamp-accurate playback. If exact replay timing is needed, the next step is an OpenEB C++ helper that opens official RAW/DAT/HDF5 containers and streams decoded events to the GUI.

## Future Work

Good next steps:

- Add a small OpenEB C++ helper if we need official RAW/DAT/HDF5 decoding inside the custom GUI.
- Add ERC controls only after verifying the board exposes an `I_ErcModule` path or an equivalent V4L2 control.
- Add ROI/RONI controls if the V4L2/media stack exposes safe sensor crop/selection controls.
- Add a screenshot update after the improved app is visually accepted on the board display.
