# KV260 Event-Visual GUI Launch Notes

## Date captured

- 2026-05-27
- Lifecycle update: 2026-05-30
- Superseded launcher update: 2026-05-30
- Desktop stall recovery update: 2026-05-31

## What was done

The native Prophesee GUI window (`metavision_viewer`) was launched on-board on display `:0` using the KV260 matchbox/X session already running.

Current preferred desktop launcher: `KV260 Event Camera`, documented in `references/kv260-event-camera-app.md`. It uses a custom GTK viewer that reads `/dev/video0` directly and avoids the three older native Metavision desktop entries.

Current on-board GUI/X state at the time of test:

- `xserver-nodm.service` was active and owns the full X/Matchbox session.
- `X :0` server process was active.
- `/tmp/.X11-unix/X0` existed (socket present).
- Matchbox process chain was present: `matchbox-window-manager`, `matchbox-desktop`, `matchbox-panel`.
- `metavision_viewer` starts on `DISPLAY=:0`.
- Runtime logs live in `~/.cache/kv260-event-viewer/`.
- The native launcher path is now kept for recovery/debugging and has a lock so duplicate clicks do not run overlapping loader/viewer processes.

## Why `event-visual` tmux looked text-only

`tmux` session `event-visual` is **text/replay/acquisition** oriented:

- it runs `v4l2-ctl` capture loops;
- it does not provide a graphical event canvas itself;
- only the `metavision_viewer` process opens the GUI window.

## Commands used successfully

On-board (prefer this if you’re already at shell on the KV260):

```bash
cd ~/Projects/kria-kv260-starter
./scripts/kv260-launch-desktop-viewer.sh --live
./scripts/kv260-event-visual-gui-local.sh --status
```

If the helper exits immediately, use this direct fallback on the board:

```bash
cd ~/Projects/kria-kv260-starter
DISPLAY=:0 XAUTHORITY=$HOME/.Xauthority nohup /usr/bin/metavision_viewer >"$HOME/.cache/kv260-event-viewer/event-visual-viewer.log" 2>&1 &
```

Useful status check:

```bash
pgrep -af '/usr/bin/metavision_viewer'
ls -l /tmp/.X11-unix/X0
```

Stop the viewer from shell:

```bash
./scripts/kv260-event-visual-gui-local.sh --stop
```

Recovery start if the camera pipeline is stale after reboot:

```bash
./scripts/kv260-launch-desktop-viewer.sh --recover
```

Remote host variant (if invoking helpers over SSH to the board):

```bash
./scripts/kv260-event-visual-gui.sh --start
./scripts/kv260-event-visual-gui.sh --status
```

## Verified output markers in viewer startup log

`~/.cache/kv260-event-viewer/event-visual-viewer.log` included:

- viewer launch help text;
- `HAL` discovery success;
- `Plugin used to open the device: hal_plugin_prophesee`;
- `Camera has been opened successfully`;
- `V4l2DataTransfer - start_impl/run_impl`.

That confirms the Prophesee stack was visible to the viewer.

## Realtime tuning guidance

If the image feels laggy, start with the low-latency mode:

```bash
cd ~/Projects/kria-kv260-starter
./scripts/kv260-event-visual-gui-local.sh --stop
./scripts/kv260-event-visual-gui-local.sh --start --low-latency
```

What this changes:

- skips continuous `.raw` recording to disk (`--low-latency` enables `--no-record`)
- disables some accessibility/dbus chatter (`NO_AT_BRIDGE=1`)
- keeps scheduling sane (safe `nice` handling; if permissions deny priority changes, it falls back to default).
- keeps Matchbox/X path stable and does not fight with tmux capture

Additional optional tweaks:

- pin viewer to one core if desired:
  `./scripts/kv260-event-visual-gui-local.sh --start --low-latency --cpu-mask 0`
- adjust priority (positive/negative):
  `... --nice -10` or `... --nice 5`

If you still see lag:

- stop other frame-heavy processes (`tmux` capture, terminals, file writes),
- reduce ROI using viewer keys (`o`, `r`, `R`, `S`),
- verify `V4l2` camera settings to lower event throughput from the device.

## Notes

- If the X server is not running, launch start with a root-capable password so the script can start X:

  ```bash
  KV260_SUDO_PASSWORD=<password> ./scripts/kv260-event-visual-gui.sh --start
  ```

- If capture is running in `tmux event-visual`, stop or pause it before GUI start, since both can race for camera ownership.

## Desktop launcher install

Create or refresh the Applications menu entries:

```bash
cd ~/Projects/kria-kv260-starter
./scripts/kv260-install-prophesee-desktop.sh --install
```

If you want the launcher installed system-wide (appears for all users):

```bash
KV260_SUDO_PASSWORD=<password> ./scripts/kv260-install-prophesee-desktop.sh --install --global
```

The `.desktop` launchers run the desktop wrapper, which delegates to the local GUI helper and switches to the `petalinux` user if the desktop shell invokes it as root:

```bash
./scripts/kv260-launch-desktop-viewer.sh --live
./scripts/kv260-launch-desktop-viewer.sh --record
```

Current intended installed launcher files:

```text
/usr/share/applications/kv260-event-camera.desktop
```

There should be no duplicate KV260/Metavision/Prophesee desktop shortcuts in `/home/petalinux/Desktop` or `/home/root/Desktop`. Native `metavision_viewer` and file transfer remain available through scripts and the Windows Control Center, but no longer appear as extra board menu launchers.

The full desktop stall recovery note is in:

```text
references/kv260-desktop-stall-recovery.md
```

The native viewer close-button issue is documented in:

```text
references/kv260-native-metavision-viewer-close-behavior.md
```

If the menu item appears to do nothing, run this recovery sequence once on the board:

```bash
# Remove stale launch state and old viewer process
pkill -f '/usr/bin/metavision_viewer' || true
rm -f "$HOME/.cache/kv260-event-viewer/event-visual-viewer.pid" \
      "$HOME/.cache/kv260-event-viewer/event-visual-viewer-launch.sh"
# legacy paths from older scripts (optional cleanup)
rm -f /tmp/event-visual-viewer.pid /tmp/event-visual-viewer-launch.sh

# Reinstall the launcher so menu uses the current wrapper
./scripts/kv260-install-prophesee-desktop.sh --remove
./scripts/kv260-install-prophesee-desktop.sh --install

# Check the result
cat "$HOME/.cache/kv260-event-viewer/metavision-viewer-launch.log"
tail -n 40 "$HOME/.cache/kv260-event-viewer/metavision-viewer-wrapper.log"
tail -n 40 "$HOME/.cache/kv260-event-viewer/event-visual-viewer.log"

# If this happens right after reboot, run a forced recovery once:
./scripts/kv260-launch-desktop-viewer.sh --recover
```

### Why the menu can briefly open a terminal/login window

This can happen when the shell launcher is reading a non-standard `DISPLAY` value such as `:0.0` or `localhost:0.0`, and the old display-socket parser looked for `/tmp/.X11-unix/X:0.0`.

A guard was added so the launcher now normalizes display values to `/tmp/.X11-unix/X0` and launches through the same direct path.

Run this quick check after clicking:

```bash
DISPLAY=${DISPLAY:-:0} ./scripts/kv260-open-prophesee-viewer.sh --start --force --low-latency --no-record
tail -n 20 "$HOME/.cache/kv260-event-viewer/metavision-viewer-launch.log"
```

If it still returns immediately, capture:

```bash
echo "DISPLAY=$DISPLAY X_SOCKET_PATH=$XAUTHORITY"
grep -E "No X socket|launcher invoked|Viewer process confirmed" "$HOME/.cache/kv260-event-viewer/metavision-viewer-launch.log"
tail -n 80 "$HOME/.cache/kv260-event-viewer/event-visual-viewer.log"
```

### Why it used to look like a "dead reopen"

There are two common causes:

1. **Viewer process exits immediately** (most often `Camera not found` from SDK init).
   This means `/usr/bin/metavision_viewer` started, then failed because the Prophesee pipeline is not ready.

   Common log marker:

   ```
   Metavision SDK Stream exception
   Error 101001: Camera not found. Check that a camera is plugged on your system and retry.
   ```

2. **Mixed launcher/runtime ownership** across root/user contexts.
   If one launch created `/tmp/event-visual-viewer.*` as root and another launch runs as `petalinux`, stale files and stale process IDs can create inconsistent close/reopen behavior.

Recovery sequence (run once):

```bash
pkill -f '/usr/bin/metavision_viewer' || true
pkill -f 'kv260-event-visual-gui-local.sh --start' || true

rm -f /tmp/event-visual-viewer.pid /tmp/event-visual-viewer-launch.sh
rm -f "$HOME/.cache/kv260-event-viewer/event-visual-viewer.pid" \
      "$HOME/.cache/kv260-event-viewer/event-visual-viewer-launch.sh"

./scripts/kv260-install-prophesee-desktop.sh --remove
./scripts/kv260-install-prophesee-desktop.sh --install
./scripts/kv260-launch-desktop-viewer.sh --recover
```

If you still see the reopen behavior, verify camera readiness first:

```bash
ls /dev/video* /dev/media* 2>/dev/null
v4l2-ctl -d /dev/video0 --all | sed -n '/Driver name\\|Pixel Format/p'
./scripts/kv260-event-visual-gui-local.sh --start --low-latency --no-record
```

`kv260-open-prophesee-viewer.sh` is still available for direct script usage, but normal menu workflow now goes through
`kv260-launch-desktop-viewer.sh --live` so repeated menu clicks do not restart the camera stack or relaunch the viewer.

## Close/restart hardening (current behavior)

A recent issue was a dead/relaunch loop from stale viewer state and mixed runtime ownership. The scripts were updated to harden this path:

- menu launcher starts live mode without force/rearm by default
- launcher enforces optional `--force`/`--recover` restart semantics
- repeated normal clicks return "already running" and preserve the same viewer process
- root-owned desktop invocation switches to `petalinux` before starting the viewer
- stop logic now validates PID-file ownership and falls back to name-based kill
- `.desktop` launcher now disables startup notify to avoid the 10s busy spinner (`StartupNotify=false`)
- `.desktop` launcher now includes `StartupWMClass=metavision_viewer`

## Desktop busy/stall recovery

On 2026-05-31 the local desktop became busy and stopped opening applications. The cause found was an orphaned `matchbox-desktop` process outside the active `xserver-nodm.service` session.

Successful recovery:

```bash
rm -f /tmp/kv260-event-camera-app.lock /tmp/kv260-metavision-viewer-toggle.lock 2>/dev/null || true

orphan_pids="$(ps -e -o pid=,ppid=,comm= | awk '$2 == 1 && $3 == "matchbox-deskto" { print $1 }')"
if [ -n "${orphan_pids}" ]; then
  printf '%s\n' '<password>' | sudo -S kill ${orphan_pids} >/dev/null 2>&1 || true
fi

printf '%s\n' '<password>' | sudo -S systemctl restart xserver-nodm
sleep 5
```

Healthy state after recovery:

```text
xserver-nodm.service active
xinit -> Xorg :0
matchbox-window-manager
matchbox-desktop
matchbox-panel
```

Both launchers were then tested:

```text
KV260 Event Camera opens and exits through its quit socket.
No second KV260/Metavision/Prophesee launcher is installed on the board desktop.
```

Note: the native `metavision_viewer` window close button can be unreliable on the KV260 Matchbox desktop. If the preview jumps to the upper-left corner or a gray UI appears during close, use the Windows Control Center native-viewer action or `./scripts/kv260-event-visual-gui-local.sh --stop --force`.

Use these commands when the window becomes unresponsive or reopens unexpectedly:

```bash
cd ~/Projects/kria-kv260-starter
./scripts/kv260-event-visual-gui-local.sh --stop --force
./scripts/kv260-event-visual-gui-local.sh --stop
./scripts/kv260-event-visual-gui-local.sh --start --force --low-latency --no-record
./scripts/kv260-event-visual-gui-local.sh --status
```

If you see a restart with "reopened but no events", do a lock reset first:

```bash
cd ~/Projects/kria-kv260-starter
./scripts/kv260-event-visual-gui-local.sh --stop --force
fuser -v /dev/video0 2>/dev/null || true
./scripts/kv260-event-visual-gui-local.sh --start --force --low-latency --no-record
```

Interpretation:

- If `fuser` reports any holder on `/dev/video0`, keep running the stop command once more and retry.
- If `event-visual-viewer.log` still shows camera-init failures, rerun with `--start --force` and check for an older viewer process still alive before launch.
- If the board exposes the Prophesee media node as `/dev/media1` (no `/dev/media0`), this repo now auto-fixes it by creating `/dev/media0 -> /dev/media1` before stack reload.

If you manually run the stack load script and still get a blank viewer, confirm the media node and video format are correct:

```bash
media-ctl -p /dev/media0 | sed -n '1,220p'
v4l2-ctl -d /dev/video1 --all | sed -n '1,60p'
```

Expected format on the active video node is `PSE*` (for example `PSE2` / `PSE1`).

If a stale desktop shortcut was created before this update, reinstall it so the launcher reflects the new behavior:

```bash
./scripts/kv260-install-prophesee-desktop.sh --remove
./scripts/kv260-install-prophesee-desktop.sh --install
```

If you see old launcher files still present, remove them manually:

```bash
rm -f "$HOME/.cache/kv260-event-viewer/event-visual-viewer.pid" \
      "$HOME/.cache/kv260-event-viewer/event-visual-viewer-launch.sh" \
      /tmp/event-visual-viewer.pid /tmp/event-visual-viewer-launch.sh
```

## Recovery for “window reopens but no events”

If the GUI window opens, closes, and reopens but stays blank/no events, run this hard reset:

```bash
cd ~/Projects/kria-kv260-starter
./scripts/kv260-event-visual-gui-local.sh --stop --force
./scripts/kv260-event-visual-gui-local.sh --stop

# optional but useful if a background process still owns /dev/video0
fuser -v /dev/video0

# full rearm + restart (force path clears stale camera ownership and reloads stack)
./scripts/kv260-launch-desktop-viewer.sh --recover
```

If that command still returns a dead/blank window, keep the log tail open while starting:

```bash
tail -f "$HOME/.cache/kv260-event-viewer/event-visual-viewer.log"
```

Then launch again with `./scripts/kv260-launch-desktop-viewer.sh --recover` and check for:
- `Camera has been opened successfully`
- no immediate `metavision::Exception` / `Camera not found` errors

If the window is still blank after this point, do an explicit sensor-path warmup (what usually fixes startup black screens after image/reboot):

```bash
cd ~/Projects/kria-kv260-starter
echo on > /sys/class/video4linux/$(basename /dev/v4l-subdev3)/device/power/control 2>/dev/null || true
export V4L2_HEAP=reserved
export V4L2_SENSOR_PATH=/dev/v4l-subdev3
./scripts/kv260-event-visual-gui-local.sh --stop --force
./scripts/kv260-launch-desktop-viewer.sh --recover
```

While launching, monitor both logs:

```bash
tail -f "$HOME/.cache/kv260-event-viewer/event-visual-viewer.log" \
       "$HOME/.cache/kv260-event-viewer/metavision-viewer-launch.log" \
       "$HOME/.cache/kv260-event-viewer/metavision-viewer-wrapper.log"
```

If you see `Camera has been opened successfully` but no motion dots/events:
- confirm physical movement is in front of the sensor
- confirm `v4l2-ctl -d "$(ls /dev/video* | head -n 1)" --all` shows `Pixel Format: 'PSE*'`.

### Why this now happens after boot

After a reboot or repeated failed launches, the board can leave:

- broken `/dev/media0` symlink target,
- `/dev/video*` nodes with no valid event pixel format,
- stale holders on `/dev/video`.

`kv260-event-visual-gui-local.sh` now validates the event-camera path before launch:

- removes stale `/dev/media0`/`/dev/media1` symlinks that point nowhere,
- runs `media-ctl` re-format passes,
- checks that the active video node reports a `PSE*` event pixel format,
- and then starts the viewer in a detached session so closing the launcher shell does not close the viewer.

Actual byte-stream probing is optional because an event camera can produce zero bytes in a static scene. Enable it only for diagnosis:

```bash
KV260_STRICT_STREAM_PROBE=1 ./scripts/kv260-event-visual-gui-local.sh --start --force --low-latency --no-record
```

So when you see a black window now, use:

```bash
KV260_SUDO_PASSWORD=<password> ./scripts/kv260-launch-desktop-viewer.sh --recover
```

One-shot recovery helper:

```bash
./scripts/kv260-recover-event-viewer.sh
```

## Why it sometimes opens a terminal and nothing else on desktop click

The most common reason is a stale `.desktop` entry pointing to an old command path (or a previous wrapper) while Matchbox is still using that menu cache.

Do this one-shot repair from the board shell:

```bash
cd ~/Projects/kria-kv260-starter
./scripts/kv260-fix-metavision-launcher.sh
```

What it does:

- Removes legacy launcher files that still contain old Metavision/Prophesee names.
- Reinstalls the launcher so it points only to the current wrapper:
  `scripts/kv260-launch-desktop-viewer.sh`.
- Optionally starts the viewer immediately with:
  `./scripts/kv260-launch-desktop-viewer.sh --recover`.

If you prefer manual verification:

```bash
cat ~/.local/share/applications/metavision-event-viewer.desktop
cat ~/Desktop/metavision-event-viewer.desktop
grep -n '^Exec=' ~/.local/share/applications/metavision-event-viewer.desktop
tail -n 80 /tmp/kv260-launch-desktop-viewer-petalinux.log
```

Then try the menu click again. If it still fails, share these exact lines:

- `~/.cache/kv260-event-viewer/metavision-viewer-launch.log`
- `~/.cache/kv260-event-viewer/metavision-viewer-wrapper.log`
- `~/.cache/kv260-event-viewer/event-visual-viewer.log`

## FAQ

### 1) Why does clicking look like it opens under root?

Short answer: the launcher can be read from two places, and the panel may be using the copy under `/usr/share/applications` (system-wide, root-owned) while your session is a user session.  

The `.desktop` file itself does **not** force a login shell; it just asks the desktop to execute a command.  
If that command resolves in a root-owned/legacy launcher entry, you can still see root-context behavior (paths like `/root`, root-owned lock files, or root-like shell prompt symptoms).

### 2) Can it be made one-click simple?

Yes. Use the repair script once and then click the same menu item only:

```bash
cd ~/Projects/kria-kv260-starter
./scripts/kv260-fix-metavision-launcher.sh
```

That makes menu entries clean and re-installs the user launcher so a plain click starts the viewer.

### 3) Why this happens if it worked before?

This is usually a stale launcher/cache mix:
- old root `.desktop` still cached, and
- a new user `.desktop` exists with a different command path.

After a reboot or package reinstall, run the fix script again.

Remove the shortcut(s):

```bash
./scripts/kv260-install-prophesee-desktop.sh --remove
```
