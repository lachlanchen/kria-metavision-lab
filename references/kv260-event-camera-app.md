# KV260 Event Camera App

Generated: 2026-05-30

## Purpose

`KV260 Event Camera` is the preferred desktop launcher for this board.

It replaces the previous three desktop entries:

- `Metavision Event Viewer`
- `Metavision Event Recorder`
- `Metavision Control Panel`

Those older entries were removed from the installed application menus because repeated clicks could start competing native viewer/recovery processes. That was the cause of the viewer reopening, closing only after multiple attempts, or opening a dead/blank native window.

## Installed Launcher

The primary desktop/menu entry is:

```text
KV260 Event Camera
```

The native SDK viewer and file-transfer GUI also have one board Applications launcher each:

```text
scripts/kv260-metavision-viewer-toggle.sh
scripts/kv260-file-transfer-gui.sh
```

Current installed files:

```text
/usr/share/applications/kv260-event-camera.desktop
/usr/share/applications/kv260-metavision-viewer.desktop
/usr/share/applications/kv260-file-transfer.desktop
```

The installer intentionally does not leave duplicate launcher copies in:

```text
/home/petalinux/Desktop
/home/root/Desktop
/home/petalinux/.local/share/applications
/home/root/.local/share/applications
```

That avoids Matchbox showing duplicate entries or launching stale commands from old desktop shortcuts.

Custom GUI launcher command:

```sh
/home/petalinux/Projects/kria-kv260-starter/scripts/kv260-event-camera-app.sh
```

Native viewer toggle command:

```sh
/home/petalinux/Projects/kria-kv260-starter/scripts/kv260-metavision-viewer-toggle.sh
```

The wrapper runs the GUI as:

```text
user: petalinux
display: :0
```

## What The App Does

The app does not depend on the native `metavision_viewer` window. It reads the KV260 event camera node directly:

```text
/dev/video0
```

Current detected camera format:

```text
Driver: psee-dma
Media model: Prophesee Video Pipeline
Pixel format: PSE2, 64-bit Prophesee EVT2.1
Size: 1280x720
```

The app decodes the PSE2/EVT2.1 V4L2 byte stream directly and renders events in a GTK window. It follows the OpenEB EVT2.1 decoder rule that only event types `0` and `1` are CD polarity events. The preview expands the EVT2.1 32-bit `vx` vector inside each 64-bit event word, so one event-vector word can draw up to 32 neighboring x positions. This avoids the vertical stripe artifact caused by drawing only the vector base x coordinate.

The current app keeps the direct V4L2 live renderer but does not paint from the capture thread. The capture thread dequeues, copies, immediately requeues, records first when recording is active, counts events, and places preview payloads in a bounded queue. The preview worker drains stale queued payloads, keeps only the newest few, updates a recent-event time surface, and renders the active pixels for the live accumulation window. If a burst is followed by a quiet/static scene, the renderer holds the last event-time surface instead of clearing to black. This keeps preview work from blocking recording or V4L2 buffer return, while avoiding the old fade-to-blank display path.

The live-preview defaults are tuned for this KV260 desktop:

```text
Display cap: 24 FPS
Preview payload cap: 4 newest payloads/frame
Recording preview cap: 2 newest payloads/frame
Preview sample cap: 4096 EVT2.1 CD words/payload
Live minimum accumulation: 200 ms
Live minimum visual radius: 1 when not recording
Hold idle event surface: on
Point radius control default: 0
```

Point radius can be increased from the Display tab. The control default remains `0`, but live preview now applies a minimum visual radius of `1` when not recording so sparse event activity does not look like a black screen. During recording-priority mode, the minimum radius is disabled unless the user explicitly increases the control, keeping recording CPU pressure lower.

## Controls

- `Open Live`: opens `/dev/video0`.
- `Close`: stops streaming or playback and releases `/dev/video0`.
- `Start Recording`: records the exact raw V4L2 PSE2 byte stream.
- `Stop Recording`: closes the recording file cleanly.
- `Recording Priority`: default on. While recording, every raw payload is queued for recording first and live preview is decimated to reduce CPU pressure. Turn it off only when recording rates are low and smoother recording-time preview matters more.
- `Recording status`: compact live counter for written MB, written buffers, writer queue depth, queue capacity, raw payload drops, and preview payloads skipped during recording priority mode.
- `Open Recording`: opens a previously captured `.pse2.raw` / raw EVT2.1 payload recording for playback.
- `Pause` / `Resume`: pauses or resumes recording playback.
- `New Name`: generates a timestamped output filename.
- `Recover Stack`: closes the stream, reloads the Prophesee camera stack, then leaves the app ready to reopen.
- `Quit`: stops streaming and closes the app.
- `Folder`: output folder for recordings.
- `File`: output filename.
- `Video node`: V4L2 node, default `/dev/video0`.
- `Playback accumulation ms`: event time window used for live preview persistence and recording playback frames.
- `FPS`: live preview and playback refresh target.
- `Palette`: dark, light, gray, or cool/warm event colors.
- `Polarity`: show all events, only ON events, or only OFF events.
- `Point radius`: event dot size. Increase this if the view looks too sparse.
- `Event trail`: recording-playback trail/persistence setting. The current live path uses the accumulation window and recent-event surface instead of the old fade buffer.
- `Playback OSD overlay`: shows source, rate, playback state, and accumulation during recording playback.

The `Biases` tab reads daily-use controls from `/dev/v4l-subdev3`:

- `bias_diff_on`
- `bias_diff_off`
- `bias_hpf`
- `bias_fo`
- `bias_refr`
- `bias_diff`

The tab can refresh live values, apply the edited values, reset defaults, and save/load JSON bias presets.

The app auto-opens the camera when launched from the desktop.

## Language Support

The board custom viewer has a language selector in the header.

Supported languages match the README and Windows Control Center language set:

```text
English
Arabic
Spanish
French
Japanese
Korean
Vietnamese
Simplified Chinese
Traditional Chinese
German
Russian
```

The selected board-viewer language is saved here:

```text
/home/petalinux/.config/kv260-event-camera-app.json
```

Launch-time override:

```sh
KV260_EVENT_CAMERA_LANG=zh-Hans DISPLAY=:0 ./scripts/kv260-event-camera-app.sh
```

Useful language codes:

```text
en ar es fr ja ko vi zh-Hans zh-Hant de ru
```

The launcher keeps `LANG=C` for this minimal PetaLinux image, but it now sets `PYTHONIOENCODING=utf-8` and the app has safe Unicode status logging. This avoids crashes when non-ASCII labels are selected while the board locale remains minimal.

## Recording Format

Default output folder:

```text
/home/petalinux/event_recordings
```

Default filename pattern:

```text
event_YYYYMMDD_HHMMSS.pse2.raw
```

Each recording also writes:

```text
event_YYYYMMDD_HHMMSS.pse2.raw.json
```

The `.raw` file is the exact V4L2 PSE2/EVT2.1 byte stream. It is useful for board-side debugging and replay tooling that understands the KV260 PSE2 stream. It is not guaranteed to be the same container format as Metavision SDK `.raw` files, because the board image does not include the Metavision Python SDK modules or C++ development headers.

The custom app can replay its own `.pse2.raw` files directly. Official Metavision RAW/DAT/HDF5 support should be added later through the installed C++ SDK runtime or a small OpenEB helper, because the Python Metavision modules are not present in this image.

Keep official RAW export separate from live capture. The stable live recorder should continue writing `.pse2.raw` plus JSON metadata, and a later converter can translate finished recordings into an official-ish Metavision RAW container without adding risk to the capture path.

## Install Or Refresh Launcher

```sh
cd /home/petalinux/Projects/kria-kv260-starter
KV260_SUDO_PASSWORD=<password> ./scripts/kv260-install-prophesee-desktop.sh --install --global
```

This installs exactly three system Applications menu entries, removes old `Metavision Event Viewer` / `Metavision Event Recorder` / `Metavision Control Panel` entries, and removes stale duplicate Desktop shortcut copies.

Expected installed entries after refresh:

```sh
find /home/petalinux/.local/share/applications /home/petalinux/Desktop \
     /home/root/.local/share/applications /home/root/Desktop \
     /usr/share/applications \
     -maxdepth 1 \( -iname '*kv260*' -o -iname '*metavision*' -o -iname '*prophesee*' \) \
     -type f 2>/dev/null | sort
```

Expected result:

```text
/usr/share/applications/kv260-event-camera.desktop
/usr/share/applications/kv260-metavision-viewer.desktop
/usr/share/applications/kv260-file-transfer.desktop
```

## Manual Launch

```sh
cd /home/petalinux/Projects/kria-kv260-starter
DISPLAY=:0 ./scripts/kv260-event-camera-app.sh
```

To launch without automatically opening the camera:

```sh
DISPLAY=:0 KV260_EVENT_APP_AUTO_OPEN=0 ./scripts/kv260-event-camera-app.sh
```

Runtime log:

```text
/home/petalinux/.cache/kv260-event-camera/app.log
```

## Verification Done

Updated smoke tests after the playback/bias/display-control upgrade:

```text
python3 -m py_compile scripts/kv260-event-camera-app.py
module import: OK
existing .pse2.raw replay decode: 59459 events from first 512 KiB, nonblank rendered frame
bias probe: bias_diff_on/off, bias_hpf, bias_fo, bias_refr, bias_diff found on /dev/v4l-subdev3
GUI smoke: starts on DISPLAY=:0 with auto-open disabled and exits through the local command socket
old commit comparison: 80910d3 live path produced 234925 events, 223 buffers, 122 frames in 5 seconds
live renderer regression fix: moved live preview to a bounded recent-event surface; the earlier fix produced 268045 events, 217 buffers, 117 frames in 5 seconds
live continuity check: after the first 2 seconds, 71 of 71 emitted frames changed instead of fading static
playback smoke: event_20260531_183748.pse2.raw decoded 59459 events from first 512 KiB and rendered nonblank
recording hot-loop robustness: payload is now copied, V4L2 buffer is requeued immediately, recording write happens before preview decode
recording smoke: 3350960 byte .pse2.raw file, recorded_bytes=3350960, replay decoded 65345 events from first 512 KiB, preview_errors=0
bounded writer robustness: default queue recording wrote 3990184 bytes across 326 buffers with drops=0, pending=0, write_error=None
small queue robustness: KV260_RECORD_QUEUE_BUFFERS=8 wrote 2379888 bytes across 231 buffers with drops=0
recording preview decimation: non-recording decoded 174/174 buffers; recording decoded 99 buffers, skipped 70 preview buffers, wrote 13695824 bytes with drops=0
recording status and priority mode: GUI shows MB/buffer/queue/drop counters; priority on decimates preview during recording; priority off decodes every payload after the recorder enqueue
multilingual import test: 11 language codes found; zh-Hans, zh-Hant, ar, and en fallback verified
multilingual GUI smoke: DISPLAY=:0, KV260_EVENT_CAMERA_LANG=zh-Hans, auto-open disabled, exited cleanly through the local command socket
2026-06-02 preview fix: EVT2.1 CD decode limited to event types 0/1; live preview now drains stale payloads and renders a bounded recent-event surface instead of the old fade canvas
2026-06-02 black-preview follow-up: direct 22 s probe stayed visible through 10-22 s; visible pixels averaged 9809 in 10-15 s and 60760 in 15-22 s
2026-06-02 GTK display-buffer fix: live image update now uses GLib.Bytes + GdkPixbuf.Pixbuf.new_from_bytes instead of wrapping raw Python bytes with new_from_data
2026-06-02 board-display screenshot after 90 s: /tmp/kv260-root-screenshot-after-90s.png showed visible event pixels; log still reported buffers=15701, active=8235
2026-06-02 strict validation: /tmp/kv260-event-camera-validation/20260602-200709/report.md
2026-06-02 live preview strict test: 18 s, 1800 V4L2 buffers, 24.1M events, 84 preview frames, 37 changed frames after 10 s, 37 active event frames after 10 s, active_max_after_10s=79068, preview_errors=0
2026-06-02 recording priority on: 21.8 MB written, 400 buffers written, drops=0, pending=0, write_error=None, active preview after 2 s
2026-06-02 recording priority off: 19.1 MB written, 400 buffers written, drops=0, pending=0, write_error=None, active preview after 2 s
2026-06-06 cap/burst follow-up: live preview now holds the last event-time surface when no new events arrive after a burst, matching native viewer behavior more closely
2026-06-06 idle hold validation: /tmp/kv260-event-camera-validation/20260606-062723/report.md; idle_surface_hold PASS, first_visible=42, held_visible=42 after 0.55 s idle
2026-06-06 dense burst cache validation: /tmp/kv260-event-camera-validation/20260606-063723/report.md; dense_idle_surface_cache PASS, active_pixels=518400, first_render_ms=220.538, held_render_ms=26.546
2026-06-06 display update check after dense-cache fix: preview region changed 31.395% over 5 s on the actual board display
```

Direct stream test:

```text
Live camera open: /dev/video0 (1280x720 PSE2)
Live: 0.07 Mev/s, buffers=38
Live: 0.04 Mev/s, buffers=88
Live: 0.05 Mev/s, buffers=133
Live: 0.05 Mev/s, buffers=176
RESULT frames=117 diffs=116 after_2s_frames=71 after_2s_diffs=71 events=268045 buffers=217
```

The fixed preview image was generated at:

```text
/tmp/kv260_event_preview_fixed.png
```

It no longer shows the vertical-strip artifact from the earlier base-x-only decoder.

GUI launch smoke test:

```text
pid=<python process>
Camera stream open: /dev/video0 (1280x720 PSE2)
```

Launcher lifecycle smoke tests after the desktop reset:

```text
KV260 Event Camera opens, accepts the local quit socket command, and exits.
Metavision Viewer opens/closes through the native viewer toggle helper.
KV260 File Transfer opens through the file-transfer helper.
Only one copy of each intended system Applications entry remains.
```

## Native Viewer Scripts

The native Metavision helper scripts are still kept in the repo for recovery and debugging:

```text
scripts/kv260-event-visual-gui-local.sh
scripts/kv260-launch-desktop-viewer.sh
scripts/kv260-metavision-control-panel.py
scripts/kv260-metavision-control-panel.sh
```

The native menu launcher path now has a lock to ignore duplicate clicks while a launch is already in progress. The stop path now waits for the native process to exit and escalates to `kill -9` only if the viewer refuses to close.

The native viewer window close-button behavior is documented separately:

```text
references/kv260-native-metavision-viewer-close-behavior.md
```

The OpenEB and bias research behind the current viewer design is documented in:

```text
references/kv260-openeb-custom-viewer-research.md
```

The recording robustness decision and the recommended minimal next improvement are documented in:

```text
references/kv260-recording-robustness.md
```
