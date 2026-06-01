# KV260 Full Setup Script

Updated: 2026-06-01

This repo provides one orchestrator for setting up the KV260 side and, optionally, installing the Windows control center over LAN SSH:

```sh
scripts/kv260-full-setup.sh
```

The script is designed to be idempotent. It can be rerun after reboot or after a successful setup.

## What It Sets Up

Board-side setup:

- creates repo-local recording folders,
- marks local helper scripts executable,
- best-effort installs GUI/runtime packages from the current PetaLinux `dnf` feed,
- enables `dropbear.socket` and `xserver-nodm.service` when present,
- installs a local X11 display never-sleep helper,
- installs `kv260-ncdu-lite.py` as `/usr/local/bin/ncdu`,
- best-effort loads the Prophesee KV260 camera stack if the loader exists,
- installs the board Applications menu launchers:
  - `KV260 Event Camera`
  - `Metavision Viewer`
  - `KV260 File Transfer`
- runs the event camera validation script.

Optional Windows setup:

- creates a Windows install directory,
- copies `scripts/windows/*` to Windows,
- runs `Install-KV260WindowsShortcuts.ps1`,
- verifies the Windows control center scripts with `-CheckOnly`.
The Windows control center includes the native `Files` tab for Windows/KV260 transfers.

## Basic Board Setup

From the repo root on the KV260:

```sh
KV260_SUDO_PASSWORD=<password> ./scripts/kv260-full-setup.sh
```

Without a password in the environment, the script will use normal `sudo` prompts where needed:

```sh
./scripts/kv260-full-setup.sh
```

Dry run:

```sh
./scripts/kv260-full-setup.sh --dry-run
```

Skip validation:

```sh
./scripts/kv260-full-setup.sh --skip-validation
```

Install only per-user launchers instead of global launchers:

```sh
./scripts/kv260-full-setup.sh --no-global-launchers
```

## Windows Control Center Setup

With key-based Windows SSH:

```sh
KV260_SUDO_PASSWORD=<password> ./scripts/kv260-full-setup.sh \
  --windows-host 192.168.1.166 \
  --windows-user Administrator \
  --windows-key /home/petalinux/.ssh/id_dropbear_rsa \
  --windows-board-alias petalinux-kv260
```

With interactive Windows SSH password prompts:

```sh
./scripts/kv260-full-setup.sh \
  --skip-packages \
  --skip-validation \
  --windows-host 192.168.1.166 \
  --windows-user Administrator \
  --windows-board-alias petalinux-kv260
```

With `sshpass` installed for non-interactive password auth:

```sh
KV260_WINDOWS_SSH_PASSWORD=<windows-password> ./scripts/kv260-full-setup.sh \
  --windows-host 192.168.1.166 \
  --windows-user Administrator
```

Default Windows install directory:

```text
C:/Users/<windows-user>/Projects/petalinux/kv260-remote-gui
```

Override:

```sh
./scripts/kv260-full-setup.sh \
  --windows-host 192.168.1.166 \
  --windows-user Administrator \
  --windows-dest C:/Users/Administrator/Projects/petalinux/kv260-remote-gui
```

## Package Behavior

PetaLinux feeds vary. The setup script installs packages one by one and treats missing optional packages as warnings.

Core packages it tries:

```text
matchbox-desktop
matchbox-terminal
matchbox-wm
matchbox-session-sato
pcmanfm
l3afpad
rxvt
xinput-calibrator
xauth
openssh-ssh
openssh-scp
sshpass
v4l-utils
python3-numpy
python3-pillow
python3-pygobject
```

If a package is absent from the feed, setup continues.

## Recording Paths

Current custom GUI recording default:

```text
/home/petalinux/Projects/kria-kv260-starter/recordings/event-camera
```

Legacy `v4l2-ctl` acquisition script output default:

```text
/home/petalinux/Projects/kria-kv260-starter/recordings/event-visual
```

Override custom GUI recording location:

```sh
KV260_EVENT_RECORD_DIR=/media/sdcard/events ./scripts/kv260-full-setup.sh
```

## Validation

The setup script runs:

```sh
./scripts/kv260-validate-event-camera.py
```

The validation checks:

- launchers,
- bias controls,
- live preview,
- recording priority on/off,
- playback of captured files,
- GUI lifecycle.

Reports go to:

```text
/tmp/kv260-event-camera-validation/YYYYMMDD-HHMMSS/report.md
```

## After Setup

Open custom GUI on the KV260 HDMI desktop:

```sh
./scripts/kv260-event-camera-switch.sh --board
```

Open through Windows SSH X11 from the Windows control center:

```text
KV260 Control Center -> Open On Windows
```

Stop all viewers:

```sh
./scripts/kv260-event-camera-switch.sh --stop-all
```

Open the board-side file transfer GUI:

```sh
./scripts/kv260-file-transfer-gui.sh
```
