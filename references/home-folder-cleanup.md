# KV260 Home Folder Cleanup

Updated: 2026-06-01

This note records the cleanup of `/home/petalinux` so source/project files live under `~/Projects` while generated event recordings stay in simple home-folder capture directories.

Update on 2026-06-01: recordings were briefly moved into the repo-local ignored `recordings/` tree. The policy is now reverted: new captures default to `/home/petalinux/event_recordings` and `/home/petalinux/event-visual`.

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

Legacy native event-visual recordings were temporarily moved:

```text
/home/petalinux/event-visual
-> /home/petalinux/Projects/kria-kv260-starter/recordings/event-visual-legacy
```

They were later moved back to:

```text
/home/petalinux/event-visual
```

Custom GUI event recordings were temporarily moved:

```text
/home/petalinux/event_recordings
-> /home/petalinux/Projects/kria-kv260-starter/recordings/event-camera
```

They were later moved back to:

```text
/home/petalinux/event_recordings
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
/home/petalinux/event_recordings
```

Legacy native `v4l2-ctl` recordings:

```text
/home/petalinux/event-visual
```

New legacy acquisition output default:

```text
/home/petalinux/event-visual
```

## Recording Defaults

The custom app, control panel, and validation script now default to:

```text
/home/petalinux/event_recordings
```

Override when needed:

```sh
KV260_EVENT_RECORD_DIR=/some/other/folder ./scripts/kv260-event-camera-app.sh
```

The legacy acquisition script now defaults to:

```text
/home/petalinux/event-visual
```

Override when needed:

```sh
KV260_EVENT_VISUAL_DIR=/some/other/folder ./scripts/kv260-event-visual-acquire-legacy.sh
```

## Git Tracking

The repo-local `recordings/` folder remains ignored by `.gitignore` for safety, but it is no longer the default capture location.

The current default keeps large `.raw` and `.pse2.raw` captures under `/home/petalinux`, outside the repo working tree.

## Validation

After the original cleanup, validation passed with the temporary repo-local recording directory:

```text
VALIDATION_RESULT=PASS
record_dir=/home/petalinux/Projects/kria-kv260-starter/recordings/event-camera
```

Current validation runs now default to:

```text
/home/petalinux/event_recordings
```

Latest cleanup validation report:

```text
/tmp/kv260-event-camera-validation/20260601-153214/report.md
```
