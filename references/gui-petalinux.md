# PetaLinux GUI Recommendation and Setup (KV260)

## Recommendation (for KV260 + Prophesee workflow)

- Keep the image headless by default. The Prophesee quickstart flow is serial/SSH-first.
- Only add on-device UI if needed for local display work.
- If you need a GUI, prefer a lightweight stack (`X11 + matchbox`) instead of a full desktop.

This is the practical tradeoff:

- **Default workflow**: headless + `minicom` + SSH (`ssh -X`)  
  Lower RAM and lower maintenance.

- **On-device UI needed**: lightweight X11 desktop  
  Add `packagegroup-petalinux-x11` and `packagegroup-petalinux-matchbox`.

## Enable lightweight GUI in `petalinux-projects`

The committed lab branch for the PetaLinux submodule already records the lightweight GUI/RDP rootfs intent:

```text
petalinux-projects branch: kv260-2022.2-kria-metavision-lab
commit: 9dd1954 Enable lightweight desktop rootfs options
```

The branch enables `packagegroup-petalinux-matchbox` and records `CONFIG_xrdp` / `CONFIG_xorgxrdp` as the attempted RDP package options. The runtime package feed did not provide usable XRDP packages on the current image, so HDMI Matchbox remains the working desktop path.

To reconfigure manually:

From the project root:

```bash
cd ~/Projects/kria-kv260-starter/petalinux-projects
petalinux-config -c rootfs
```

In rootfs package groups, enable:

- `packagegroup-petalinux-x11`
- `packagegroup-petalinux-matchbox`

Save and exit, then rebuild:

```bash
petalinux-build
petalinux-package --wic --bootfiles "ramdisk.cpio.gz.u-boot,boot.scr,Image,system.dtb,system-zynqmp-sck-kv-g-revB.dtb"
```

Re-flash SD card after build (as you already use for the base image).

## What to use after boot

On-device:

- Start Xorg/session if needed (exact launch depends on your image layer layout).

On host:

- Use SSH forwarding for viewer workflows when possible:

```bash
ssh -X root@<board-ip>
```

## Why not full desktop by default

- Larger rootfs and image size.
- Higher RAM pressure.
- More updates/package conflicts when kernel/driver stack changes.
- More risk for field-reliable capture/reboot behavior on KV260.

## Useful references

- PetaLinux Package Groups (2022.2)
- Adding a PetaLinux package group
- AMD Zynq UltraScale+ graphics options (`x11`, `wayland`, `fbdev`)
