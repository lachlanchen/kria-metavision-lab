# KV260 Home Folder Cleanup

Updated: 2026-06-01

This note records the cleanup of `/home/petalinux` so project files live under `~/Projects` and generated recordings do not clutter the home directory.

## What `event-visual` Was

`/home/petalinux/event-visual` was a legacy native acquisition folder created before the custom GUI recorder existed.

It was used by:

```text
/home/petalinux/event-visual-acquire.sh
```

That script ran an infinite `v4l2-ctl` capture loop:

```text
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=200 --stream-to=<file>
```

It wrote rolling `.raw` files plus `loop.log` and `session.log`. It was useful early in bring-up, but it is not the current recommended recorder. The current recommended recorder is the custom GUI:

```text
scripts/kv260-event-camera-app.py
```

## Moves Completed

Legacy native event-visual recordings:

```text
/home/petalinux/event-visual
-> /home/petalinux/Projects/kria-kv260-starter/recordings/event-visual-legacy
```

Custom GUI event recordings:

```text
/home/petalinux/event_recordings
-> /home/petalinux/Projects/kria-kv260-starter/recordings/event-camera
```

Legacy acquisition script:

```text
/home/petalinux/event-visual-acquire.sh
-> /home/petalinux/Projects/kria-kv260-starter/scripts/kv260-event-visual-acquire-legacy.sh
```

Temporary duplicate acquisition script:

```text
/home/petalinux/.tmp_event_visual_acquire.sh
-> removed
```

Old top-level references folder:

```text
/home/petalinux/references/kv260-prophesee-resources.md
-> /home/petalinux/Projects/kria-kv260-starter/references/archive/home-kv260-prophesee-resources-20260526.md
```

The active, newer reference file remains:

```text
/home/petalinux/Projects/kria-kv260-starter/references/kv260-prophesee-resources.md
```

Standalone KRobotics FPGA checkout:

```text
/home/petalinux/fpga-projects
-> /home/petalinux/Projects/krobotics-fpga-projects
```

Temporary extracted KRobotics FPGA archive:

```text
/home/petalinux/fpga-projects-archived
-> /home/petalinux/Projects/krobotics-fpga-projects-archived
```

The repo symlink was updated:

```text
Projects/kria-kv260-starter/krobotics-fpga-projects
-> /home/petalinux/Projects/krobotics-fpga-projects
```

## Current Layout

Main project:

```text
/home/petalinux/Projects/kria-kv260-starter
```

OpenEB reference clone:

```text
/home/petalinux/Projects/openeb
```

KRobotics FPGA reference clone:

```text
/home/petalinux/Projects/krobotics-fpga-projects
```

Current custom GUI recordings:

```text
/home/petalinux/Projects/kria-kv260-starter/recordings/event-camera
```

Legacy native `v4l2-ctl` recordings:

```text
/home/petalinux/Projects/kria-kv260-starter/recordings/event-visual-legacy
```

New legacy acquisition output default:

```text
/home/petalinux/Projects/kria-kv260-starter/recordings/event-visual
```

## Recording Defaults

The custom app, control panel, and validation script now default to:

```text
/home/petalinux/Projects/kria-kv260-starter/recordings/event-camera
```

Override when needed:

```sh
KV260_EVENT_RECORD_DIR=/some/other/folder ./scripts/kv260-event-camera-app.sh
```

The legacy acquisition script now defaults to:

```text
/home/petalinux/Projects/kria-kv260-starter/recordings/event-visual
```

Override when needed:

```sh
KV260_EVENT_VISUAL_DIR=/some/other/folder ./scripts/kv260-event-visual-acquire-legacy.sh
```

## Git Tracking

The `recordings/` folder is intentionally ignored by `.gitignore`.

That means large `.raw` files stay on disk for experiments but are not pushed to GitHub.

## Validation

After the cleanup, the event camera validation passed and confirmed the new default recording directory:

```text
VALIDATION_RESULT=PASS
record_dir=/home/petalinux/Projects/kria-kv260-starter/recordings/event-camera
```

Latest cleanup validation report:

```text
/tmp/kv260-event-camera-validation/20260601-153214/report.md
```
