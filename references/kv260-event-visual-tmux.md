# KV260 `event-visual` tmux (petalinux user)

## Why you saw “need UTF-8 locale”

`tmux` on this board requires a UTF-8 locale. The login shell often defaults to `ANSI_X3.4-1968`.
Prefix tmux calls with:

```bash
LC_ALL=en_GB.UTF-8 LC_CTYPE=en_GB.UTF-8 LANG=en_GB.UTF-8
```

## Why “No such file or directory” happened for `/tmp//tmux-1000/default`

That socket path is the **default user-scoped tmux socket**.  
`petalinux` and `root` use different UID/socket namespaces by default.

Use a dedicated socket name via `-L` to avoid this mismatch:

```bash
tmux -L kv260-event-visual ...
```

## Recommended command flow (petalinux user)

From repo:

```bash
cd ~/Projects/kria-kv260-starter
./scripts/kv260-event-visual-petalinux.sh --board <kv260-ip> --user petalinux --video /dev/video0 --start
./scripts/kv260-event-visual-petalinux.sh --board <kv260-ip> --user petalinux --attach
```

This session is **capture-only** (text / process output). It will not render
the event GUI because the viewer is a separate X/GTK application.

For the native GUI demo (on board shell):

```bash
./scripts/kv260-event-visual-gui-local.sh --start
./scripts/kv260-event-visual-gui-local.sh --status
```

Status only:

```bash
./scripts/kv260-event-visual-petalinux.sh --board <kv260-ip> --user petalinux --status
```

Stop:

```bash
./scripts/kv260-event-visual-petalinux.sh --board <kv260-ip> --user petalinux --stop
```

## One-shot raw commands (if you prefer no helper script)

```bash
ssh petalinux@<kv260-ip> \
  "LC_ALL=en_GB.UTF-8 LC_CTYPE=en_GB.UTF-8 LANG=en_GB.UTF-8 \
tmux -L kv260-event-visual new-session -d -s event-visual '/usr/bin/v4l2-ctl -d /dev/video0 --stream-count=10 --stream-mmap --stream-to=/tmp/event-visual-test.raw'"

ssh petalinux@<kv260-ip> \
  "LC_ALL=en_GB.UTF-8 LC_CTYPE=en_GB.UTF-8 LANG=en_GB.UTF-8 \
   tmux -L kv260-event-visual attach -t event-visual"
```
