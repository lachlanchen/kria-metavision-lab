# KV260 Metavision Control Panel

Superseded: the installed desktop launcher is now `KV260 Event Camera`, documented in `references/kv260-event-camera-app.md`. This older native-control panel is kept in the repository for reference and debugging only.

## Purpose

The control panel is a local X11 GUI for the Prophesee event camera on the KV260. It wraps the native `metavision_viewer` process instead of replacing the renderer.

This keeps the proven SDK viewer for event display, while adding a simpler local control surface for:

- opening live view;
- opening record mode with a chosen folder and `.raw` filename;
- sending the native viewer's SPACE record toggle;
- closing the viewer cleanly;
- running camera recovery when the pipeline is stale;
- passing common `metavision_viewer` settings.

## Desktop Entry

Installed menu/desktop item:

```text
Metavision Control Panel
```

Command:

```bash
/home/petalinux/Projects/kria-kv260-starter/scripts/kv260-metavision-control-panel.sh
```

The wrapper normalizes `DISPLAY`, uses the `petalinux` user when invoked by a root-owned desktop shell, and logs to:

```text
/tmp/kv260-metavision-control-panel-petalinux.log
```

## Files

```text
scripts/kv260-metavision-control-panel.py
scripts/kv260-metavision-control-panel.sh
scripts/kv260-event-visual-gui-local.sh
scripts/kv260-install-prophesee-desktop.sh
```

The GUI uses Python plus Xlib through `ctypes`. This was chosen because the current PetaLinux image does not provide Tkinter, PyQt, GTK Python bindings, `zenity`, or `yad`.

## Controls

- `Record folder`: output directory for raw event recordings.
- `File name`: selected `.raw` filename. If `.raw` is omitted, it is added.
- `X display`: usually `:0`.
- `Camera config JSON`: passed to `metavision_viewer -j`.
- `Biases file`: passed to `metavision_viewer -b`.
- `Output config JSON`: passed to `metavision_viewer --output-camera-config`.
- `ROI x y w h`: passed to `metavision_viewer -r`.
- `Subsampling r c`: passed to `metavision_viewer -d`.

Buttons:

- `Open Live`: starts live low-latency view without recording.
- `Open Record`: starts the viewer with `-o <selected raw file>`.
- `Toggle Rec`: sends SPACE to the Metavision Viewer window through XTest.
- `Close Viewer`: stops `metavision_viewer` cleanly through the helper.
- `Recover Camera`: runs the force+rearm recovery path.
- `Status`: shows viewer/camera status.
- `New Name`: creates a timestamped filename.
- `Make Folder`: creates the selected recording folder.

## Recording Behavior

`Open Record` sets the output path by launching:

```bash
metavision_viewer -o /selected/folder/name.raw
```

The native viewer still controls recording with SPACE. Use either:

- press SPACE in the Metavision Viewer window; or
- click `Toggle Rec` in the control panel.

The panel does not rewrite or decode the event stream. Recorded data is the native Metavision `.raw` output.

## Smooth Launch Behavior

Normal live opening is non-destructive:

```bash
kv260-event-visual-gui-local.sh --start --no-force --no-rearm --no-record --low-latency
```

Recording uses a selected output file:

```bash
kv260-event-visual-gui-local.sh --start --force --no-rearm --record --output-file /path/to/file.raw
```

Plain `--force` now restarts the viewer without rearming the camera stack. Full camera reload is reserved for:

```bash
kv260-launch-desktop-viewer.sh --recover
```

This separation keeps close/open/record actions faster and avoids unnecessary camera pipeline reloads.

## Install Or Refresh Desktop Entries

```bash
cd ~/Projects/kria-kv260-starter
KV260_SUDO_PASSWORD=<password> ./scripts/kv260-install-prophesee-desktop.sh --install --global
```

Installed entries:

- `Metavision Event Viewer`
- `Metavision Event Recorder`
- `Metavision Control Panel`

## Verification

Checked on the board:

- control panel opens on `DISPLAY=:0` as `petalinux`;
- menu entries are installed under both user and system application directories;
- custom recording output path launches the native viewer with `-o`;
- normal live viewer was restored afterward.
