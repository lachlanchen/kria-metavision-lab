# KV260 Desktop Stall Recovery

Generated: 2026-05-31

## Symptom

The local HDMI desktop can show a busy cursor and stop opening applications. The event camera launchers may also appear to do nothing even though the X server is still running.

## Root Cause Found

The board had an orphaned `matchbox-desktop` process with parent PID `1`, while the active `matchbox-panel`, window manager, and X server were managed by `xserver-nodm.service`.

That mixed desktop state can leave Matchbox using stale launcher state and can make new desktop clicks look busy or ignored.

The old duplicate launcher layout made this easier to trigger because Matchbox could see multiple `.desktop` files for the same camera tools from different locations.

## Current Stable Launcher Layout

Only these Prophesee/KV260 application entries should exist:

```text
/usr/share/applications/kv260-event-camera.desktop
/usr/share/applications/kv260-file-transfer.desktop
```

There should be no duplicate KV260/Metavision/Prophesee entries under:

```text
/home/petalinux/Desktop
/home/root/Desktop
/home/petalinux/.local/share/applications
/home/root/.local/share/applications
```

Verify:

```sh
find /home/petalinux/.local/share/applications /home/petalinux/Desktop \
     /home/root/.local/share/applications /home/root/Desktop \
     /usr/share/applications \
     -maxdepth 1 \( -iname '*kv260*' -o -iname '*metavision*' -o -iname '*prophesee*' \) \
     -type f 2>/dev/null | sort
```

## Recovery Used Successfully

Run this locally on the board:

```sh
cd /home/petalinux/Projects/kria-kv260-starter

rm -f /tmp/kv260-event-camera-app.lock \
      /tmp/kv260-metavision-viewer-toggle.lock 2>/dev/null || true

orphan_pids="$(ps -e -o pid=,ppid=,comm= | awk '$2 == 1 && $3 == "matchbox-deskto" { print $1 }')"
if [ -n "${orphan_pids}" ]; then
  printf '%s\n' '<password>' | sudo -S kill ${orphan_pids} >/dev/null 2>&1 || true
fi

printf '%s\n' '<password>' | sudo -S systemctl restart xserver-nodm
sleep 5
```

If you are already root, the restart can simply be:

```sh
systemctl restart xserver-nodm
```

## Healthy State

After recovery, this should be true:

```sh
systemctl is-active xserver-nodm
systemctl status xserver-nodm --no-pager -l | sed -n '1,80p'
```

Expected service tree:

```text
xinit /etc/X11/Xsession -- /usr/bin/Xorg :0 -br -pn
/usr/bin/Xorg :0 -br -pn
matchbox-window-manager -theme Sato -use_cursor yes
matchbox-desktop
matchbox-panel --start-applets ...
settings-daemon
```

The key point is that `matchbox-desktop` and `matchbox-panel` are children of the same `xserver-nodm.service` session, not separate orphaned processes.

## Launcher Tests

Custom GUI:

```sh
cd /home/petalinux/Projects/kria-kv260-starter
DISPLAY=:0 XAUTHORITY=/home/petalinux/.Xauthority ./scripts/kv260-event-camera-app.sh
```

The app should open once. If it is already running, the wrapper sends a `present` command instead of starting a duplicate process.

Native Metavision viewer:

```sh
cd /home/petalinux/Projects/kria-kv260-starter
DISPLAY=:0 XAUTHORITY=/home/petalinux/.Xauthority ./scripts/kv260-metavision-viewer-toggle.sh
```

First launch opens `/usr/bin/metavision_viewer`. Running the same command again closes it.

Current verified behavior:

```text
KV260 Event Camera: opens and closes through its local quit socket.
Metavision Viewer: one launch opens the native viewer; a second launch closes it.
Desktop entries: only the two system Applications entries remain.
```

## If The Desktop Gets Busy Again

Use the full recovery sequence above instead of repeatedly clicking launchers. Repeated clicks can queue startup-notify state and make it harder to tell whether the problem is the desktop shell or the camera process.

After recovery, reinstall the launcher entries if needed:

```sh
cd /home/petalinux/Projects/kria-kv260-starter
KV260_SUDO_PASSWORD=<password> ./scripts/kv260-install-prophesee-desktop.sh --install --global
```
