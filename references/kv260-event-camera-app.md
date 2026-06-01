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

The native SDK viewer is kept as a separate one-click toggle:

```text
Metavision Viewer
```

Current installed files:

```text
/usr/share/applications/kv260-event-camera.desktop
/usr/share/applications/kv260-metavision-viewer.desktop
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

The app decodes the PSE2/EVT2.1 V4L2 byte stream directly and renders events in a GTK window. The preview expands the EVT2.1 32-bit `vx` vector inside each 64-bit event word, so one event-vector word can draw up to 32 neighboring x positions. This avoids the vertical stripe artifact caused by drawing only the vector base x coordinate.

The current app keeps the original known-good live renderer: every live PSE2 payload is painted immediately, then the canvas decays between frames. Recording playback uses the newer EVT2.1 timestamp path with a Metavision-style accumulation window. This split is intentional: the timestamp accumulator is useful for recordings, but it made the live camera show an initial burst and then fade/static on this board.

## Controls

- `Open Live`: opens `/dev/video0`.
- `Close`: stops streaming or playback and releases `/dev/video0`.
- `Start Recording`: records the exact raw V4L2 PSE2 byte stream.
- `Stop Recording`: closes the recording file cleanly.
- `Open Recording`: opens a previously captured `.pse2.raw` / raw EVT2.1 payload recording for playback.
- `Pause` / `Resume`: pauses or resumes recording playback.
- `New Name`: generates a timestamped output filename.
- `Recover Stack`: closes the stream, reloads the Prophesee camera stack, then leaves the app ready to reopen.
- `Quit`: stops streaming and closes the app.
- `Folder`: output folder for recordings.
- `File`: output filename.
- `Video node`: V4L2 node, default `/dev/video0`.
- `Playback accumulation ms`: event time window used for recording playback frames.
- `FPS`: live preview and playback refresh target.
- `Palette`: dark, light, gray, or cool/warm event colors.
- `Polarity`: show all events, only ON events, or only OFF events.
- `Point radius`: event dot size. Increase this if the view looks too sparse.
- `Event trail`: live-display persistence/decay. The default is `0.820`, matching the older working preview behavior.
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

## Install Or Refresh Launcher

```sh
cd /home/petalinux/Projects/kria-kv260-starter
KV260_SUDO_PASSWORD=<password> ./scripts/kv260-install-prophesee-desktop.sh --install --global
```

This installs the two system Applications menu entries, removes old `Metavision Event Viewer` / `Metavision Event Recorder` / `Metavision Control Panel` entries, and removes stale Desktop shortcut copies.

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
live renderer regression fix: restored immediate draw-and-decay live path; current path produced 268045 events, 217 buffers, 117 frames in 5 seconds
live continuity check: after the first 2 seconds, 71 of 71 emitted frames changed instead of fading static
playback smoke: /home/petalinux/event_recordings/event_20260531_183748.pse2.raw decoded 59459 events from first 512 KiB and rendered nonblank
recording hot-loop robustness: payload is now copied, V4L2 buffer is requeued immediately, recording write happens before preview decode
recording smoke: 3350960 byte .pse2.raw file, recorded_bytes=3350960, replay decoded 65345 events from first 512 KiB, preview_errors=0
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
Metavision Viewer opens the native /usr/bin/metavision_viewer process, then the same launcher closes it.
Only the two system Applications entries remain.
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
