# KV260 GUI Deep Research (Prophesee + PetaLinux + KV260)

I reviewed the Prophesee workflow and AMD GUI/display documentation and converted it into a practical playbook for this board stack.

## Ground truth

- Prophesee KV260 Starter Kit image is documented as headless-first; UART is required for setup.
- UART path is typically `/dev/ttyUSB1` at `115200 8N1`.
- Viewer workflow is the same as documented in the Prophesee app deployment guide:
  - On-board HDMI: start Xorg and run viewer on `DISPLAY=:0.0`.
  - Host route: `ssh -X`/`ssh -Y` and run viewer from your PC as remote X client.

## Can I “show” the desktop from here?

Not directly in this chat terminal session. I can provide exact commands, and once you run one of the methods below on a real board terminal, the desktop/image will render:

- Physical HDMI monitor on KV260 (`DISPLAY=:0.0`), or
- PC X server over SSH forwarding.

## Minimal on-device GUI (recommended baseline)

If you rebuild the image:

1. `petalinux-config -c rootfs`
2. Enable:
   - `packagegroup-petalinux-x11`
   - `packagegroup-petalinux-matchbox`
   - (`packagegroup-petalinux-qt` only if you need Qt examples)
3. Save, rebuild:
   - `petalinux-build`
   - `petalinux-package --wic ...`

Why this combo:

- `packagegroup-petalinux-x11` gives the X11 display foundation.
- `packagegroup-petalinux-matchbox` gives a lightweight WM and terminal.
- Keep it far lighter than XFCE/GNOME and more reliable for KV260 constraints.

## Display backend decision (KV260 practical)

AMD’s Mali 400 stack documents four backend modes: `fbdev`, `x11`, `wayland`, `headless`.

For most Prophesee viewer use:

- `x11` + matchbox: best balance for desktop debugging and `metavision_viewer`.
- `wayland` (`weston`) only if you need modern Wayland flow and have enough effort budget.
- `fbdev/headless`: only for specific non-desktop or compute-only workflows.

## Show the GUI: working command sets

### A. Local HDMI on board

```sh
# board serial console
load-prophesee-kv260-<imx636|genx320>.sh
Xorg -depth 16 &
export V4L2_HEAP=reserved
export V4L2_SENSOR_PATH=/dev/v4l-subdev3
echo on > /sys/class/video4linux/v4l-subdev3/device/power/control
DISPLAY=:0.0 metavision_viewer
```

If X fails to come up:

```sh
systemctl status xserver-nodm
journalctl -u xserver-nodm --no-pager -n 120
tail -n 120 /var/log/Xorg.0.log
ls -l /dev/fb0 /dev/dri/card0
```

### B. Host-driven X11 forwarding (no HDMI needed)

```sh
ssh -X root@<board-ip>
export V4L2_HEAP=reserved
export V4L2_SENSOR_PATH=/dev/v4l-subdev3
echo on > /sys/class/video4linux/v4l-subdev3/device/power/control
metavision_viewer
```

If `ssh -X` is restricted by security policy:

```sh
ssh -Y root@<board-ip>
```

## Optional auto-start notes

- If this works reliably and you want GUI at boot:
  - start/enable `xserver-nodm` after validating permissions and display output.
- Keep services minimal by default; CLI-first image is still valid for day-to-day development.

## Camera interface routing note (important for your normal-camera test)

KV260 connector roles to keep straight:

- `J7` (IAS0): IAS camera interface with onsemi AP1302 ISP path.
- `J8` (IAS1): IAS interface directly connected to the PS HPA/FPGA path.
- `J9`: Raspberry Pi 15-pin camera interface.

The Prophesee starter overlay currently binds IMX636 and exposes only event stream
`/dev/video0` (`PSE2`). If your camera is a standard frame module on J8, it will
need a matching frame-sensor overlay/driver path instead of the Prophesee IMX636 stack.

## Source documents used

- Prophesee KV260 app deployment:
  - https://docs.prophesee.ai/amd-kria-starter-kit/application/app_deployment.html
- Prophesee KV260 starter kit manual:
  - https://docs.prophesee.ai/amd-kria-starter-kit/kv260-starter-kit-manual.html
- Prophesee GitHub project docs (Prophesee PetaLinux deployment commands):
  - https://github.com/prophesee-ai/petalinux-projects
- PetaLinux package groups:
  - https://xilinx-wiki.atlassian.net/wiki/spaces/A/pages/2282979331/PetaLinux%2BPackage%2BGroups%2B-%2B2022.2%2BRelease
- PetaLinux package-group workflow:
  - https://docs.amd.com/r/2022.2-English/ug1144-petalinux-tools-reference-guide/Adding-a-Package-Group?contentId=VA4CS6FAiGq0BusdYG8i_g
- Mali backend options and x11/wayland/headless discussion:
  - https://xilinx-wiki.atlassian.net/wiki/spaces/A/pages/18841928/Zynq%2BUltraScale%2BMPSoC%2B-%2BMali%2B400
