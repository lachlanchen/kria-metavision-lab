# KV260 Camera Viewer Script

## About the camera you saw on J8

`13MP Auto Focus RGB Camera Module (AR1335)` is a standard frame camera module.
If you are using a Prophesee event-stack image, that camera can be physically present and still not
visible as `/dev/video*` as a frame source, because the active Prophesee overlay routes the camera pipeline
to event mode (`PSE2`) on `/dev/video0`.

That means:

- You **can** use that camera on the board as a frame source in a frame-camera configuration.
- On the current event image stack, you likely **cannot** use it directly as a normal V4L2 frame device without
  changing the active FPGA/kernel path to an AR1335/J8-compatible frame pipeline.

## Current board status

- On this KV260 stack the current overlay is Prophesee (`prophesee-kv260-imx636`),
  and `/dev/video0` reports event format `PSE2`.
- If you need a regular frame camera on IAS1 (J8), this image is not yet configured
  for a generic frame path by default.

## Does KV260 include a frame camera?

Not by default. On Prophesee KV260 Starter Kit, `/dev/video` is the event-stream
device from the IMX636/GenX320 sensor (`PSE*` pixel format) when the starter-kit
load scripts are active.

You may have a separate frame camera only if you connect one manually (e.g. USB
V4L2 camera).

## Run one launcher for event + frame cameras

From the KV260 shell:

```bash
cd ~/Projects/kria-kv260-starter
./scripts/kv260-camera-viewer.sh --start
```

What this does:

- Detects available `/dev/video*` devices.
- Classifies as `event` when pixel format looks like `PSE*`.
- Starts:
  - `metavision_viewer` for event camera, or
  - a local OpenCV frame viewer for frame camera.
- Requires local X socket at `/tmp/.X11-unix/X0` (`DISPLAY=:0` by default).

## Useful commands

```bash
./scripts/kv260-camera-viewer.sh --list
./scripts/kv260-camera-viewer.sh --status
./scripts/kv260-camera-viewer.sh --stop
```

Force a specific type:

```bash
./scripts/kv260-camera-viewer.sh --type event --start
./scripts/kv260-camera-viewer.sh --type frame --start --frame-fps 30
```

If your frame camera uses a specific node, pass it explicitly:

```bash
./scripts/kv260-camera-viewer.sh --type frame --start --video /dev/video1 --frame-fps 30
```

If reopening the event viewer gives a blank window or no stream:

```bash
cd ~/Projects/kria-kv260-starter
./scripts/kv260-camera-viewer.sh --type event --stop
./scripts/kv260-event-visual-gui-local.sh --stop --force
./scripts/kv260-camera-viewer.sh --type event --start --low-latency --no-record --rearm
```

If it still reopens blank, run direct local recovery:

```bash
./scripts/kv260-event-visual-gui-local.sh --stop --force
./scripts/kv260-event-visual-gui-local.sh --start --force --low-latency --no-record --rearm
```

If the event window opens but remains blank, run the strict probe path:

```bash
KV260_SUDO_PASSWORD=<password> ./scripts/kv260-event-visual-gui-local.sh --stop --force
KV260_SUDO_PASSWORD=<password> ./scripts/kv260-event-visual-gui-local.sh --start --force --rearm --low-latency --no-record
```

This performs a media-node repair and verifies PSE stream output before showing the viewer window.

Or one-shot:

```bash
./scripts/kv260-recover-event-viewer.sh
```

### J8 default frame camera behavior

If the camera you connected is a normal frame camera on J8 (IAS1), it is expected to be
non-visible while the Prophesee event stack is loaded. The active overlay makes `/dev/video0`
an event node (`PSE2`), not a standard frame stream.

On the current checked image, AP1302 support is built into the kernel, but there is no active
AP1302/AR1335 device-tree/media graph and no installed AR1335/AP1302/J8 overlay package.
So this cannot be fixed by installing only a userspace viewer package.

Use this check:

```bash
cd ~/Projects/kria-kv260-starter
./scripts/kv260-camera-viewer.sh --list
./scripts/kv260-camera-viewer.sh --type frame --start
./scripts/kv260-ias1-j8-check.sh
```

If `--type frame` reports no non-PSE camera, the system is still in event-only mode and
needs a new overlay/kernel path for a frame sensor.

Low-latency event viewing:

```bash
./scripts/kv260-camera-viewer.sh --start --type event --low-latency --no-record
```

Frame viewer options:

```bash
./scripts/kv260-camera-viewer.sh --start --type frame --frame-width 1280 --frame-height 720
```

If you only want event stream GUI, stop capture-text sessions before starting:

```bash
./scripts/kv260-event-visual-petalinux.sh --board <kv260-ip> --user petalinux --stop
./scripts/kv260-camera-viewer.sh --type event --start
```

## Deep camera discovery (one command)

Run this from the KV260 shell to get an evidence-based view of all camera-facing
paths:

```bash
cd ~/Projects/kria-kv260-starter
./scripts/kv260-camera-deep-scan.sh --quick
```

For deeper transport checks (USB/I2C/firmware/kernel log correlation):

```bash
./scripts/kv260-camera-deep-scan.sh --full
```

If this scan shows only Prophesee-style `PSE` video nodes, the board is in event-only mode.
That is expected for the current `imx636` overlay and does not mean your normal camera is broken.
To expose a standard frame camera node, you need a matching frame-camera overlay/driver path for
that connector (`J7/J8`) and, if needed, a dual-camera design path.

Detailed IAS1/J8 findings are in:

```text
references/kv260-ias1-j8-frame-camera.md
```

## Notes

- The frame viewer depends on `python3` + `cv2` (`opencv-python`) on KV260.
- If `cv2` is missing, install your OpenCV package in the image or use another
  V4L2 viewer.

### IAS1/J8 vs frame cameras

Board connector roles (from KV260 interface docs):

- `J7 (IAS0)` uses onsemi AP1302 ISP.
- `J8 (IAS1)` is a 4-lane IAS interface directly connected to the HPA bank (FPGA).
- `J9` is the Raspberry Pi 15-pin camera connector.

Because this Prophesee image loads an event pipeline overlay for IMX636, a frame
camera on IAS1 J8 is expected to remain invisible as `/dev/video*` unless you change
the PL/kernel/drivers to match that frame sensor.
