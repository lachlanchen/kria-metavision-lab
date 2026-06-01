# KV260 Disk Usage

Generated: 2026-05-31

## Filesystem Layout Observed

The current PetaLinux root filesystem and `/home` are on the same SD-card partition:

```text
/dev/mmcblk1p2 mounted on /
size: 3.8G
used: about 2.9G
free: about 751M
```

So `/home` only appears to have about 3.8 GB because it is not a separate large partition. It shares the root filesystem.

Large home-directory items observed before cleanup:

```text
/home/petalinux/event-visual       about 942M
/home/petalinux/.nvm               about 441M
/home/petalinux/.npm               about 265M
/home/petalinux/.codex             about 114M
/home/petalinux/Projects           about 22M
```

Cleanup on 2026-06-01 briefly moved the large event recording folders into the starter project:

```text
/home/petalinux/Projects/kria-kv260-starter/recordings/event-visual-legacy
/home/petalinux/Projects/kria-kv260-starter/recordings/event-camera
```

The `recordings/` directory is ignored by git, so these large `.raw` files stay local and are not pushed to GitHub.

That policy was later reverted for usability. New captures default back to:

```text
/home/petalinux/event_recordings
/home/petalinux/event-visual
```

## `ncdu` Package Status

The board has `dnf`, but the current PetaLinux package feed does not provide an `ncdu` package:

```text
No match for argument: ncdu
Error: Unable to find a match: ncdu
```

The board also does not have a C compiler installed, so building official `ncdu` on-device would require a larger toolchain install.

## Installed Local Replacement

This repo provides a small Python/curses browser:

```text
scripts/kv260-ncdu-lite.py
```

It is installed as:

```text
/usr/local/bin/ncdu
```

Usage:

```sh
sudo ncdu /
```

Non-interactive summary:

```sh
sudo ncdu --summary /
sudo ncdu --summary /home/petalinux
```

Keys:

```text
up/down or k/j       move
enter/right/l        open directory
left/backspace/h     parent directory
r                    rescan
?                    help
q                    quit
```

For `ncdu /`, the tool skips pseudo or separate runtime filesystems such as `/proc`, `/sys`, `/dev`, `/run`, `/tmp`, `/var/volatile`, and `/configfs`, which keeps the scan focused on SD-card rootfs usage.
