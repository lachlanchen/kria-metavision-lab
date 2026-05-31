# Upstream Submodules

Generated: 2026-05-31

This repository keeps the upstream Prophesee, AMD/Kria, and LogicTronix project trees as Git submodules instead of flattening them into the main app repository.

## Why

The upstream trees are independent projects with their own history and licenses. Keeping them as submodules makes the main repository smaller, keeps upstream ownership clear, and lets the custom KV260 viewer app evolve separately from the board support sources.

## Submodule Map

| Path | Source | Branch | Purpose |
| --- | --- | --- | --- |
| `event-vitisai-app` | `LogicTronixInc/Kria-Prophesee-Event-VitisAI` | `main` | Optional Vitis AI event demo from LogicTronix / Prophesee / AMD work |
| `fpga-projects` | `prophesee-ai/fpga-projects` | `main` | Prophesee KV260 FPGA project sources |
| `linux-sensor-drivers` | `prophesee-ai/linux-sensor-drivers` | `kernel-5.15` | IMX636 and GenX320 Linux sensor drivers |
| `petalinux-projects` | `lachlanchen/petalinux-projects` | `kv260-2022.2-kria-metavision-lab` | PetaLinux project branch with local GUI/RDP rootfs config experiments |
| `zynq-video-drivers` | `prophesee-ai/zynq-video-drivers` | `kernel-5.15` | Zynq video pipeline drivers used by the kit |

## PetaLinux Lab Branch

The `petalinux-projects` submodule points to:

```text
https://github.com/lachlanchen/petalinux-projects
branch: kv260-2022.2-kria-metavision-lab
commit: 9dd1954 Enable lightweight desktop rootfs options
```

That branch is based on Prophesee upstream:

```text
https://github.com/prophesee-ai/petalinux-projects
branch: kv260-2022.2
base commit: feb34f7
tag: kv260-20251003
```

Local delta in the lab branch:

```text
project-spec/configs/rootfs_config
  CONFIG_packagegroup-petalinux-matchbox=y

project-spec/meta-user/conf/user-rootfsconfig
  CONFIG_xrdp
  CONFIG_xorgxrdp

.gitignore
  *.pre-rdp-*
```

The Matchbox option records the lightweight on-device GUI path. The XRDP entries record the attempted RDP package intent, but the current board image package feed did not provide usable `xrdp` / `xorgxrdp` binaries during runtime testing.

For the current working HDMI desktop and custom event-camera GUI, rebuilding the SD image is not required.

## Clone

Fresh clone with submodules:

```sh
git clone --recurse-submodules https://github.com/lachlanchen/kria-metavision-lab.git
```

Existing clone:

```sh
git submodule update --init --recursive
```

Check pinned commits:

```sh
git submodule status
```

## Updating A Submodule

Use this pattern when intentionally updating an upstream pointer:

```sh
git -C <submodule-path> fetch --all --tags
git -C <submodule-path> checkout <branch>
git -C <submodule-path> pull --ff-only
git add <submodule-path>
git commit -m "Update <submodule-path> submodule"
```

For `petalinux-projects`, push custom changes to the `lachlanchen/petalinux-projects` fork first, then commit the updated gitlink in this repo.
