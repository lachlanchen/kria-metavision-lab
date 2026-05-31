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

The desktop/menu entry is:

```text
KV260 Event Camera
```

Installed files:

```text
/usr/share/applications/kv260-event-camera.desktop       # single applications-menu entry
/home/root/Desktop/kv260-event-camera.desktop            # root-owned Matchbox desktop shortcut
/home/petalinux/Desktop/kv260-event-camera.desktop       # petalinux Desktop copy
```

Launcher command:

```sh
/home/petalinux/Projects/kria-kv260-starter/scripts/kv260-event-camera-app.sh
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

## Controls

- `Open Camera`: opens `/dev/video0`.
- `Close Camera`: stops streaming and releases `/dev/video0`.
- `Start Recording`: records the exact raw V4L2 PSE2 byte stream.
- `Stop Recording`: closes the recording file cleanly.
- `New Name`: generates a timestamped output filename.
- `Recover Stack`: closes the stream, reloads the Prophesee camera stack, then leaves the app ready to reopen.
- `Quit`: stops streaming and closes the app.
- `Folder`: output folder for recordings.
- `File`: output filename.
- `Device`: V4L2 node, default `/dev/video0`.
- `Persistence`: event trail decay.
- `Point Radius`: event dot size. Increase this if the view looks too sparse.

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

## Install Or Refresh Launcher

```sh
cd /home/petalinux/Projects/kria-kv260-starter
KV260_SUDO_PASSWORD=<password> ./scripts/kv260-install-prophesee-desktop.sh --install --global
```

This installs the single `KV260 Event Camera` menu entry, installs one shortcut for the root-owned Matchbox desktop, and removes the old three Metavision launchers from local and system application folders.

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

Direct stream test:

```text
Camera stream open: /dev/video0 (1280x720 PSE2)
Live: 0.15 Mev/s, buffers=24
SUMMARY events=163116 buffers=38 frames=24
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

## Native Viewer Scripts

The native Metavision helper scripts are still kept in the repo for recovery and debugging:

```text
scripts/kv260-event-visual-gui-local.sh
scripts/kv260-launch-desktop-viewer.sh
scripts/kv260-metavision-control-panel.py
scripts/kv260-metavision-control-panel.sh
```

The native menu launcher path now has a lock to ignore duplicate clicks while a launch is already in progress. The stop path now waits for the native process to exit and escalates to `kill -9` only if the viewer refuses to close.
