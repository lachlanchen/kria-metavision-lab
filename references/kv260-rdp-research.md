# KV260 RDP + X11 Deep Research (2026-05-27)

## Why we care

For the Prophesee KV260 image, the official Prophesee flow is console-first: the image ships without a windowing system and serial (`/dev/ttyUSB1`) is required for baseline setup [docs](https://docs.prophesee.ai/amd-kria-starter-kit/application/app_deployment.html#setting-up-the-board-and-application-deployment-L126-L127). The same guide shows two supported viewer paths:

- local monitor path over HDMI/DisplayPort using `Xorg` + `DISPLAY=:0.0`
- remote Linux host with `ssh -X`

This means xrdp is an optional convenience layer on top of an existing X stack, not the default path.

## Source facts used

- Prophesee KV260 guide uses the same two modes for `metavision_viewer`: local X server and `ssh -X` [docs](https://docs.prophesee.ai/amd-kria-starter-kit/application/app_deployment.html#setting-up-the-board-and-application-deployment-L239-L260).
- PetaLinux package groups for KV260/2022.2 include:
  - `packagegroup-petalinux-x11` and `packagegroup-petalinux-matchbox` as valid groups
  - matchbox group includes matchbox desktop tooling (`matchbox-desktop`, `matchbox-terminal`, session files, etc.)
  - matchbox install message appears as the path to get a desktop once installed and rebooted.
  (PetaLinux package group reference, and UG1144 examples.)
- AMD Mali docs show the graphics backend choices are `fbdev`, `X11`, `wayland`, `headless`; switching to X11 pairs with at least one window manager such as matchbox.
- xrdp defaults:
  - service is an RDP server that serves an X window desktop (not a native Windows shell) [man page](https://manpages.ubuntu.com/manpages/plucky/en/man8/xrdp.8.html)
  - default listening port is `3389`
  - xrdp supports Xorg as session type with `code=20` in `xrdp.ini` [xrdp sample ini](https://raw.githubusercontent.com/neutrinolabs/xrdp/devel/xrdp/xrdp.ini.in)
  - sesman startup flow references `startwm.sh` and user window manager behavior [sesman sample ini](https://raw.githubusercontent.com/neutrinolabs/xrdp/devel/sesman/sesman.ini.in)
  - xrdp + xorgxrdp recipes exist in OpenEmbedded (`xrdp`, `xorgxrdp`).

Deep links on X11 transport:

- AMD graphics documentation for ZynqMP-Mali says valid display backends are `fbdev`, `X11`, `wayland`, and `headless`, and recommends enabling X11 with `libmali-xlnx` plus at least one window manager such as matchbox.
- The xrdp man page explicitly states the protocol exposes an X window desktop to the client, not a Windows shell, which means the target still needs a valid X user session path (`startwm.sh` + WM).
- xrdp’s `xrdp.ini` default session `code` values are `0` (Xvnc), `10` (X11rdp), and `20` (Xorg + xorgxrdp). We target `20`.

## Connection architecture

You need a valid image for one of these transport paths:

- **Embedded GUI on HDMI/DisplayPort**
  - Must start an X server locally with `DISPLAY=:0.0` and launch `metavision_viewer`.
  - Works with no remote desktop protocol on board.
- **SSH X forwarding (`ssh -X`)**
  - Keep board headless and use host X server.
  - Lowest overhead on KV260 image contents.
- **RDP (`mstsc`)**
  - Adds `xrdp` + `xorgxrdp` on top of X11.
  - Useful when you want Windows-native client workflow.

## Practical comparison: what to install

### 1) Headless + SSH/X11-forwarding (default for this project)

Pros:
- least extra packages
- closer to Prophesee guidance
- easier to keep image size small and deterministic

Use when:
- you only need occasional GUI windows for debugging
- you already have board connected via ethernet + keyboard/monitor if needed

### 2) Local embedded GUI only (matchbox + X11)

Pros:
- on-board GUI for direct interaction
- predictable with event viewer

Cons:
- increases image size and RAM
- adds boot-time surface area

Enable both:
- `packagegroup-petalinux-x11`
- `packagegroup-petalinux-matchbox`

### 3) RDP via xrdp/xorgxrdp

Pros:
- easiest Windows client workflow once configured
- no dedicated monitor/keyboard needed

Cons:
- extra services (`xrdp`, `xrdp-sesman`) and config to keep stable
- can fail if backend modules are mismatched
- still depends on systemd services working in production image

## Recommended sequence (least risk first)

1. Keep Prophesee default startup path until Linux image boots and sensor loads successfully.
2. Add X11 + matchbox only if you need an on-device desktop.
3. Add xrdp stack:
   - `CONFIG_xrdp`
   - `CONFIG_xorgxrdp`
4. Build and flash.
5. After first boot, run target hardening helper (below).
6. Only then connect with Windows RDP and validate viewer flow.

## Host-side setup script flow

Use the repo helper in `~/Projects/kria-kv260-starter`:

```bash
cd ~/Projects/kria-kv260-starter
bash scripts/kv260-rdp-setup.sh --generate-target-script
```

Script does:
- ensures `CONFIG_packagegroup-petalinux-x11=y`
- ensures `CONFIG_packagegroup-petalinux-matchbox=y` (unless `--skip-matchbox`)
- appends `CONFIG_xrdp` and `CONFIG_xorgxrdp` into `meta-user/conf/user-rootfsconfig`
- generates `scripts/kv260-rdp-target-commands.sh`

If you just want a preview:

```bash
bash scripts/kv260-rdp-setup.sh --dry-run
```

## Target helper (post-flash) and validation

```bash
./scripts/kv260-rdp-target-commands.sh <kv260-ip> <user>
./scripts/kv260-rdp-target-commands.sh --local
```

Helper checks:
- validates `xrdp` exists
- checks `startwm.sh`, `xrdp.ini`, `sesman.ini`
- checks port `3389` listener
- enables/restarts `xrdp` and `xrdp-sesman` (default; can be skipped with `--skip-service-restart`)
- prints service status

For a safer first boot, recommended flow:

```bash
./scripts/kv260-rdp-target-commands.sh --repair-startwm --skip-service-restart <kv260-ip> <user>
./scripts/kv260-rdp-target-commands.sh --repair-startwm <kv260-ip> <user>
./scripts/kv260-rdp-target-commands.sh --local --repair-startwm
```

Example:

```bash
./scripts/kv260-rdp-target-commands.sh <kv260-ip> root
```

## Latest local check (2026-05-27)

- Local host in this workspace is `<kv260-ip>`.
- Windows host is `<windows-ip>`.
- Current target probe:
  - `nc -zv <kv260-ip> 3389`/`ss -ltnp | grep 3389` shows no RDP listener on the board.
  - `nc -zv <windows-ip> 3389` times out from the board, so there is no active host RDP endpoint to test against in this session.
  - LAN sweep of `192.168.1.1-254` found only `.1`, `.100`, `.166` as reachable in this session.
  - `dnf` package checks for `xrdp` and `xorgxrdp` return **No matches found** in the current repo set.
- Interpretation:
  - Current workspace IP model is `<kv260-ip>` for local shell context.
  - When RDP/SSH should point to the board over LAN, use the reachable KV260 address in `KV260_BOARD_IP` and `--board`.
- Runtime hardening check:
  - Updated `scripts/kv260-rdp-target-commands.sh` to fail fast when target equals local host IPv4.
  - Script now auto-detects SSH client type:
    - Avoids OpenSSH-only flags on Dropbear (`ssh -V`-based guard).
  - Command results:
  - `./scripts/kv260-rdp-target-commands.sh <kv260-ip> root` -> `ERROR: target ... matches local host`.
  - `./scripts/kv260-rdp-target-commands.sh <kv260-ip> petalinux --skip-service-restart` -> `target equals local host; remote mode blocked by guard`.
  - `./scripts/kv260-rdp-target-commands.sh --local --repair-startwm --skip-service-restart` -> `xrdp package not installed`.

## Windows client connect

From Windows:

- `mstsc /v:<kv260-ip>:3389` (after xrdp is installed and active)
- or open Remote Desktop and set `<kv260-ip>:3389`

Use a non-root user for production.

## Why this avoids risk

- Prophesee’s guidance does not require RDP, so adding it is intentionally additive.
- `xrdp` is useful but optional; you can keep the robust UART + SSH workflow if GUI stability is the priority.

## Sources

- Prophesee KV260 deployment: https://docs.prophesee.ai/amd-kria-starter-kit/application/app_deployment.html
- PetaLinux package groups: https://xilinx-wiki.atlassian.net/wiki/pages/viewpage.action?pageId=2282979331
- PetaLinux package-group docs: https://xilinx-wiki.atlassian.net/wiki/pages/viewpage.action?navigatingVersions=true&pageId=2541256718
- Mali backend selection guidance: https://xilinx-wiki.atlassian.net/wiki/pages/18841928/Xilinx%2BMALI%2Bdriver
- xrdp man page: https://manpages.ubuntu.com/manpages/plucky/en/man8/xrdp.8.html
- xrdp.ini sample: https://raw.githubusercontent.com/neutrinolabs/xrdp/devel/xrdp/xrdp.ini.in
- sesman.ini sample: https://raw.githubusercontent.com/neutrinolabs/xrdp/devel/sesman/sesman.ini.in
- xrdp project: https://www.xrdp.org/
- OpenEmbedded xrdp recipes: https://layers.openembedded.org/rrs/recipe/476093/
- OpenEmbedded xorgxrdp recipes: https://layers.openembedded.org/rrs/recipe/476092/
