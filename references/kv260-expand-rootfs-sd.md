# KV260 Expand Root Filesystem To Full SD Card

Generated: 2026-05-31

## Why This Is Needed

The 64 GB SD card is visible to Linux as about 59.5 GiB, but the Prophesee/PetaLinux image created only:

```text
/dev/mmcblk1p1   2G   /boot
/dev/mmcblk1p2   4G   /
unused space    ~53G  after p2
```

The root filesystem and `/home` share `/dev/mmcblk1p2`, so `/home` only has the same small capacity as `/`.

## Script

Canonical repo copy:

```text
scripts/kv260-expand-rootfs-sd.sh
```

Installed board-maintenance copy:

```text
/home/petalinux/SystemMaintenance/expand-rootfs-sd.sh
```

The folder name uses the correct spelling: `SystemMaintenance`.

## Usage

Check current state:

```sh
sudo /home/petalinux/SystemMaintenance/expand-rootfs-sd.sh --status
```

Dry-run:

```sh
sudo /home/petalinux/SystemMaintenance/expand-rootfs-sd.sh --dry-run
```

Grow:

```sh
sudo /home/petalinux/SystemMaintenance/expand-rootfs-sd.sh
```

Grow only part of the baseline free space:

```sh
sudo /home/petalinux/SystemMaintenance/expand-rootfs-sd.sh --free-percent 25
sudo /home/petalinux/SystemMaintenance/expand-rootfs-sd.sh --free-percent 50
sudo /home/petalinux/SystemMaintenance/expand-rootfs-sd.sh --free-percent 75
sudo /home/petalinux/SystemMaintenance/expand-rootfs-sd.sh --free-percent 100
```

`--free-percent` means "use this percent of the free space that existed when the script first captured its baseline." This is intentionally not "use this percent of whatever free space remains today", because that would grow a little more every time and would not be idempotent.

The default is `--free-percent 100`.

Grow to an absolute root-partition size:

```sh
sudo /home/petalinux/SystemMaintenance/expand-rootfs-sd.sh --target-size 16G
```

Supported suffixes are `K`, `M`, `G`, and `T`; they are interpreted as binary units. For example, `16G` means 16 GiB total root-partition size.

The script only grows. If the current root partition is already larger than the requested absolute target, it will not shrink it; it will report that the partition is already at or beyond the requested target.

If the partition table grows but the kernel still sees the old size, reboot and run the same command again:

```sh
sudo reboot
sudo /home/petalinux/SystemMaintenance/expand-rootfs-sd.sh
```

If you started with a partial target, the script saves that target in:

```text
/home/petalinux/SystemMaintenance/expand-rootfs-sd.state
```

So after reboot, running the script again without arguments continues the saved target. To intentionally grow further later, pass a larger target explicitly:

```sh
sudo /home/petalinux/SystemMaintenance/expand-rootfs-sd.sh --free-percent 75
sudo /home/petalinux/SystemMaintenance/expand-rootfs-sd.sh --target-size 32G
```

## Idempotency

The script is safe to run repeatedly:

- before reboot: grows the partition table if there is free space after root;
- after reboot: runs `resize2fs` if the kernel now sees the larger partition;
- after completion: detects that the partition is already full size and `resize2fs` becomes a harmless no-op.
- with partial growth: uses the saved baseline and target percentage so repeated runs do not keep consuming more space.
- with absolute-size growth: uses the saved target size so repeated runs continue the same target after reboot.

## Safety Checks

The script:

- detects the mounted root filesystem automatically;
- requires root filesystem type `ext4`;
- refuses to grow if the root partition is not the last partition on the disk;
- backs up the partition table before changing it;
- saves a baseline state file for idempotent partial expansion;
- uses `partprobe` / `partx` after partition changes;
- prints final `df -hT /` status.

Backups are written to:

```text
/home/petalinux/SystemMaintenance/backups/
```
