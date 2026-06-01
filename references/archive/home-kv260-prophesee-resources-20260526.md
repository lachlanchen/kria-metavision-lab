# Prophesee KV260 / Metavision Starter Kit — Local Documentation Notes

Date collected: Tue May 26, 2026

## Actions completed

- Cloned `krobotics/fpga-projects` into:
  - `/home/petalinux/fpga-projects`
- The repository is now a live git checkout on branch `main` (origin: `origin/main`).

Note:
- Earlier in this run, a temporary archive extraction was used only because `git` was initially unavailable.

## Source links captured

- https://www.prophesee-cn.com/quickstart-prophesee-metavision-starter-amd-kria-kv260/
- https://docs.prophesee.ai/amd-kria-starter-kit/application/app_deployment.html
- https://docs.prophesee.ai/amd-kria-starter-kit/kv260-starter-kit-manual.html
- https://www.amd.com/en/products/system-on-modules/kria/k26/kv260-vision-starter-kit/event-based-vision-starter-kit.html
- https://www.prophesee.ai/event-based-metavision-amd-kria-starter-kit/
- https://github.com/krobotics/fpga-projects
- https://support.prophesee.ai/portal/en/kb/prophesee-1/metavision-evks-rdks/embedded-starter-kits/starter-kit-amd-kria-kv260
- https://support.prophesee.ai/portal/en/kb/articles/starter-kit-amd-kria-kv260-release-notes
- https://support.prophesee.ai/portal/en/kb/articles/starter-kit-amd-kria-kv260

## Support Center article: Starter Kit – AMD Kria KV260 (user-captured text)

- This is the Knowledge Center landing page for the kit itself and includes:
  - direct documentation link to:
    - https://docs.prophesee.ai/amd-kria-starter-kit/kv260-starter-kit-manual.html
  - start recommendation:
    - begin with “Setting up the Board and Application Deployment”.
- Kit summary:
  - Works with AMD Kria KV260 FPGA development board.
  - supports IMX636 and GenX320 event sensors.
  - goal: evaluate/develop event-based embedded vision with customizable app examples.
- Download links listed:
  - Linux image for microSD card flashing.
  - RPM packets for upgrading from previous versions.
  - SDK with toolchain (md5 listed: `7397d862bb6c98d7eb64328b8922f51d`) for cross-compiling.
  - Active Marker source code archive.
- Source code repositories mentioned:
  - FPGA project: https://github.com/prophesee-ai/fpga-projects
  - Petalinux kernel/project links:
    - https://github.com/prophesee-ai/petalinux-projects
    - https://github.com/prophesee-ai/linux-sensor-drivers
    - https://github.com/prophesee-ai/zynq-video-drivers
  - Event ML reference app:
    - https://github.com/LogicTronixInc/Kria-Prophesee-Event-VitisAI
- CCAM5 sensor module hardware files listed:
  - `CCAM5_Pi_RevB_BOM.xlsx`
  - `CCAM5_Pi_RevB_SCH.PDF`
  - `CCAM5_Pi_RevC_SCH.PDF`
  - `CCAM5_Pi_IMX636_Assembly.step`
- Active marker pico code:
  - archive `rpi-pico-active-marker.zip` (16 KB, updated 5 months ago in the article context).
  - README in archive contains instructions for changing LED modulation/code.

## Addendum: Prophesee support access

- The page reiterates support flow:
  - as a customer, request access to:
    - knowledge center
    - personal ticketing tool
    - application notes
    - product manuals
    - SDK download resources

## Prophesee Support KC page notes

- Canonical page URL:
  - `support.prophesee.ai/portal/en/kb/prophesee-1/metavision-evks-rdks/embedded-starter-kits/starter-kit-amd-kria-kv260`
- The page is mostly gated behind customer access in this environment. Visible content includes:
  - Current release note item visible: v1.1.1 (`03/10/2025`).
  - A link to release notes.
  - Link to request Prophesee access.
- Canonicalized path note: this is where your provided short URL resolves.

### Visible release notes (v1.1.1)

- V4L2 sensor driver updates:
  - GenX320
    - Updated default bias values for latest MP spec.
    - Expanded ranges:
      - `bias_diff_on: [24; 78]`
      - `bias_diff_off: [19; 127]`
      - `bias_fo: [19; 50]`
    - Added synchronization I/O control.
    - Added camera control interface debug trace.
  - IMX636
    - Fixed `bias_refr` initialization sequence.
    - Updated default `bias_diff` to `0x4d`.
    - Extended `bias_fo` to `[45; 140]`.
    - Added synchronization I/O control.
  - OpenEB SDK
    - Fixed IMX636 bias relative-range control.
  - Active Marker
    - Updated GenX320 `bias_fo` in camera config file.

### Access flow captured from support page

- The Prophesee resources access page lists:
  - request Knowledge Center for Starter Kit customers.
  - access to application notes, product manuals, SDK download center, ticketing.

## What the Prophesee quickstart page says

- 7-step path to getting started:
  1. Purchase AMD Kria KV260 Vision AI Starter Kit.
  2. Connect the Metavision starter kit to the Discovery/Starter Kit; verify flex-cable orientation.
  3. Create a Prophesee Knowledge Center account for support content.
  4. Open the KV260 Starter Kit Manual quickstart section for SD card + firmware.
  5. Launch the Active Marker demo instructions.
  6. Move to advanced documentation to build your own application.
  7. Publish or share work on the community.
- It points to manual pages, support channels, and GitHub/resources.

## What `app_deployment.html` provides (KV260 Starter Kit Manual v1.0.0)

- Emphasizes there is no windowing system on the Prophesee image; UART access is mandatory for app launch.
- SD card prep:
  - Download the Prophesee Kria Starter Kit Linux image.
  - Minimum microSD size: **16 GB**.
  - Flash with AMD “Setting up the SD Card Image” process.
- Hardware hookup:
  - Connect sensor module flex to **J9** (RPi connector) with board powered OFF.
  - Ensure flex stiffener orientation is correct.
- UART setup:
  - Connect micro-USB from **J4** to host.
  - Identify port with `sudo dmesg | grep ttyUSB` (typically ttyUSB1).
  - Use `minicom` at `115200 8N1` with no flow control.
- Powering:
  - Connect AC power after UART setup, login with `root/root`.
- Ethernet:
  - Use Ethernet on J10.
  - Board can receive DHCP or be assigned static IP from UART (example: `ip addr add 192.168.42.1/24 dev eth0` on board).
- Application load:
  - Run `/usr/bin/load-prophesee-kv260-<sensor>.sh` (confirm success with message ending: `prophesee-kv-260-imx636: loaded to slot 0`).
- Sensor power and test:
  - `echo on > /sys/class/video4linux/v4l-subdev3/device/power/control`
  - Run `metavision_viewer` via UART+Xorg or SSH (`ssh -X` route).
  - Alternative raw capture commands are available: `yavta` and `v4l2-ctl`.

## What `kv260-starter-kit-manual.html` summarizes

- Manual sections listed:
  - Quick Start (`Design Overview`, `Setting up the Board and Application Deployment`)
  - Tutorials (`Active Markers`, `Video Pipeline Setup`, `Edit Kria Applications`, `Updating Prophesee Packages`)
  - Project architecture and repository references.
- Support note: online docs cover common topics; advanced content via Prophesee Knowledge Center/account.

## AMD product page highlights

- The AMD page describes the starter kit as an edge solution with event-based IMX636 package and active-marker demo.
- Sensor spec highlights captured:
  - IMX636 CCAM5, 1280x720
  - Latency <100 µs @1000 lux
  - Dynamic range >120 dB (80 mlux–100 klux)
  - Data interface: MIPI CSI-2 D-PHY
- “What’s inside” includes:
  - AMD Kria KV260 Starter Kit + Prophesee IMX636 CCAM5 board
  - Prophesee Linux driver/software stack and demo app

## `krobotics/fpga-projects` repository snapshot

Location: `/home/petalinux/fpga-projects`

Key files:
- `README.md`
- `SETUP.md`
- `USAGE.md`
- `projects/kv260/README.md`
- `ip/axis_tkeep_handler_2_0/`
- `ip/event_stream_smart_tracker_2_0/`
- `ip/ps_host_if_3_0/`
- `scripts/create_project.tcl`
- `scripts/create_ip_sim_project.tcl`

Quick usage (from repo docs):

```bash
cd /home/petalinux/fpga-projects
source /tools/Xilinx/Vivado/2022.2/settings64.sh
./scripts/create_project.tcl -tclargs kv260
vivado build/projects/kv260/kv260.xpr
```

IP simulation examples:

```bash
./scripts/create_ip_sim_project.tcl -tclargs --project_name axis_tkeep_handler_2_0 --run
./scripts/create_ip_sim_project.tcl -tclargs --project_name event_stream_smart_tracker_2_0 --run
```

## Notes on verification

- `prophesee-kv-260-imx636` workflow references Prophesee software stack and image details not fully visible in this environment due remote page structure, but the required high-level flow and key commands were captured from official docs.
