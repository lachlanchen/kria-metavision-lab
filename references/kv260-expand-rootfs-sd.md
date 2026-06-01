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

If the partition table grows but the kernel still sees the old size, reboot and run the same command again:

```sh
sudo reboot
sudo /home/petalinux/SystemMaintenance/expand-rootfs-sd.sh
```

## Idempotency

The script is safe to run repeatedly:

- before reboot: grows the partition table if there is free space after root;
- after reboot: runs `resize2fs` if the kernel now sees the larger partition;
- after completion: detects that the partition is already full size and `resize2fs` becomes a harmless no-op.

## Safety Checks

The script:

- detects the mounted root filesystem automatically;
- requires root filesystem type `ext4`;
- refuses to grow if the root partition is not the last partition on the disk;
- backs up the partition table before changing it;
- uses `partprobe` / `partx` after partition changes;
- prints final `df -hT /` status.

Backups are written to:

```text
/home/petalinux/SystemMaintenance/backups/
```
