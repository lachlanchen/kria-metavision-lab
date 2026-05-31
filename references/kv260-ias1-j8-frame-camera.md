# KV260 IAS1/J8 AR1335 Frame Camera Check

## Problem

Find the normal frame camera on IAS1/J8 and open a viewer without rebuilding the
PetaLinux image or FPGA design.

## Current result

On this booted Prophesee image, the IAS1/J8 frame camera is **not exposed** as a
normal V4L2 frame camera.

Current local evidence:

- `/dev/video0` exists, but it is the Prophesee event camera:
  - driver: `psee-dma`
  - media model: `Prophesee Video Pipeline`
  - format: `PSE2`
- no non-PSE `/dev/videoN` frame node exists.
- active media graph contains `imx636 6-003c`, not AP1302/AR1335.
- AP1302 support is built into the kernel, but there is no AP1302/AR1335 device
  tree node in the active device tree.
- installed overlays are:
  - `prophesee-kv260-imx636`
  - `prophesee-kv260-genx320`
  - `k26-starter-kits`
- no installed AR1335/AP1302/IAS frame-camera firmware overlay is present.
- package-feed search did not show an installable AR1335/AP1302/IAS frame-camera
  app package.

## Why a userspace install is not enough

The AR1335 on J8 is not a USB/UVC camera. It is a MIPI/IAS direct path into the
FPGA fabric. A viewer package can only display an existing `/dev/videoN` frame
node; it cannot create the FPGA pipeline, media graph, sensor device-tree node,
or V4L2 capture path.

The kernel already has the `ap1302` driver built in:

```text
name:           ap1302
filename:       (builtin)
description:    ON Semiconductor AP1302 ISP driver
```

That means the blocker is not simply "install a `.ko` driver". The missing pieces
are a matching device tree plus FPGA/video pipeline app for this camera path.

## Official hardware/doc notes

AMD UG1089 lists the KV260 peripherals:

- smart-camera app: IAS camera sensor ISP interface `J7`, OnSemi AR1335.
- functionally tested: IAS camera sensor ISP interface `J7`, OnSemi AR0144/AR1335.
- functionally tested: IAS camera sensor direct interface `J8`, OnSemi AR1335.

AMD Kria application docs say:

- `J7` is connected to a dedicated onsemi AP1302 ISP.
- `J8` is an IAS connector interfaced directly to the FPGA.
- adding sensors on `J8` requires a supporting PL implementation.

Sources:

- AMD UG1089 Supported Peripherals: https://docs.amd.com/r/en-US/ug1089-kv260-starter-kit/Supported-Peripherals
- AMD/Xilinx KV260 Integrating New IAS Sensor Modules: https://xilinx.github.io/kria-apps-docs/kv260/2022.1/build/html/docs/integrating_new_sensors.html
- AMD/Xilinx KV260 BIST Board Setup: https://xilinx.github.io/kria-apps-docs/kv260/2022.1/build/html/docs/bist/docs/setup_kv260.html

## Reproducible check

Run:

```bash
cd ~/Projects/kria-kv260-starter
./scripts/kv260-ias1-j8-check.sh
```

Include package-feed checks:

```bash
./scripts/kv260-ias1-j8-check.sh --with-packages
```

If a frame camera ever appears as a non-PSE `/dev/videoN`, open it with:

```bash
./scripts/kv260-ias1-j8-check.sh --start-viewer
```

or:

```bash
./scripts/kv260-camera-viewer.sh --type frame --video /dev/videoN --start
```

## No-rebuild path decision

No-rebuild is possible only if one of these exists for this exact kernel/image:

- a prebuilt KV260 AR1335/AP1302/IAS app package with `.dtbo` + `.bit.bin`;
- or a matching firmware bundle that creates a non-PSE V4L2 frame node;
- or a vendor-provided RPM/package feed containing that app.

As checked on this image, none of those are installed or available in the current
package feed. So the current answer is:

```text
No: this board image cannot expose the J8 normal frame camera by installing only
a userspace viewer or standalone driver package.
```

The practical options are:

- keep using the Prophesee event camera on this image;
- use a USB/UVC frame camera for a normal frame viewer without rebuilding;
- obtain a prebuilt KV260 AR1335/AP1302/IAS camera app/overlay matching this
  PetaLinux release;
- or build/rebuild a matching PL + device-tree + V4L2 pipeline.
