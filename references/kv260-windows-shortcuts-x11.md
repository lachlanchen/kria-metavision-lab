# KV260 Windows Launcher And SSH X11

Generated: 2026-05-31

## Goal

Provide one Windows entry point for the custom `KV260 Event Camera` GUI while keeping the normal KV260 HDMI desktop launcher working.

The installed Windows shortcut is:

```text
KV260 Event Camera
```

It opens a small control panel with these actions:

| Button | Result |
| --- | --- |
| `Open On Windows` | Starts VcXsrv if needed, switches the camera to SSH-X11 mode, and shows the GUI on Windows. |
| `Open On KV260 Display` | Switches the camera to the board HDMI desktop (`DISPLAY=:0`). |
| `Stop All Viewers` | Stops both custom GUI modes and releases `/dev/video0`. |
| `Status` | Shows which side is running and whether `/dev/video0` has an owner. |

The board-local Applications menu still uses:

```text
KV260 Event Camera
```

That menu item opens or raises the app directly on the KV260 HDMI desktop.

## Board Services

The board SSH listener is Dropbear socket activation:

```sh
systemctl is-enabled dropbear.socket
systemctl is-active dropbear.socket
```

Current verified state:

```text
dropbear.socket: enabled, active
xserver-nodm.service: enabled, active
```

`dropbear.socket` means the SSH service is started automatically on demand after boot. `xserver-nodm.service` keeps the local X11/Matchbox desktop available on the HDMI display.

## Board-Side Launchers

Mode switcher used by every Windows entry point:

```text
scripts/kv260-event-camera-switch.sh
```

Local HDMI launcher:

```text
scripts/kv260-event-camera-app.sh
```

SSH X11 launcher:

```text
scripts/kv260-event-camera-x11.sh
```

The X11 launcher intentionally preserves the forwarded `DISPLAY` value, such as:

```text
localhost:10.0
```

The HDMI launcher intentionally normalizes `DISPLAY` to:

```text
:0
```

This separation avoids the old problem where an SSH-X11 launch was accidentally redirected back to the board HDMI desktop.

## Camera Ownership Behavior

The event camera stream is exclusive. Only one process can own:

```text
/dev/video0
```

The switcher makes this explicit:

| Requested mode | What happens first |
| --- | --- |
| `Open On Windows` | Stops the KV260 desktop GUI, stops the native viewer if needed, waits for `/dev/video0`, then starts the SSH-X11 GUI. |
| `Open On KV260 Display` | Stops the SSH-X11 GUI, stops the native viewer if needed, waits for `/dev/video0`, then starts the board desktop GUI. |
| `Stop All Viewers` | Stops both custom GUI modes and the native viewer helper path. |

If `/dev/video0` is still owned after a normal close request, the switcher escalates against the process that still owns that camera node. This prevents the common failure where the second GUI opens but cannot show events because the first GUI still owns the camera.

The custom app still has a small Unix socket command channel. Re-running the same mode does not create duplicate windows:

- if the app is already open, the launcher sends `present`;
- if it is not open, the launcher starts it;
- `Close Camera` releases `/dev/video0`;
- `Quit` exits the GUI.

## Windows Files Installed

The Windows-side scripts are staged here:

```text
%USERPROFILE%\Projects\petalinux\kv260-remote-gui
```

Installed shortcuts:

```text
%USERPROFILE%\Desktop\KV260 Event Camera.lnk
%APPDATA%\Microsoft\Windows\Start Menu\Programs\KV260\KV260 Event Camera.lnk
```

Windows does not provide a reliable supported command-line API for silently pinning arbitrary shortcuts to the taskbar. Use the Start Menu `KV260` folder, then right-click the shortcut and choose `Pin to taskbar`.

The older direct shortcuts are intentionally removed from the Desktop by the installer:

```text
KV260 Event Camera - Board Desktop.lnk
KV260 Event Camera - Windows X11.lnk
```

Their PowerShell scripts remain available under `%USERPROFILE%\Projects\petalinux\kv260-remote-gui` for debugging, but the normal workflow is the single `KV260 Event Camera` shortcut.

## Windows Prerequisites

Verified on Windows:

```text
OpenSSH client: C:\WINDOWS\System32\OpenSSH\ssh.exe
VcXsrv: C:\Program Files\VcXsrv\vcxsrv.exe
Windows sshd service: Running, Automatic
```

`VcXsrv` is only needed for the `Windows X11` shortcut. The `Board Desktop` shortcut does not need a Windows X server because the window appears on the KV260 HDMI desktop.

This SSH warning is benign when the GUI window appears:

```text
Warning: No xauth data; using fake authentication data for X11 forwarding.
```

It means the Windows SSH client did not have an `xauth` cookie to forward. VcXsrv still accepts the connection in this setup, so the real test is whether the GUI opens and events render.

## Reinstall Windows Shortcuts

From the KV260 board, copy the Windows helper scripts:

```sh
scp -i /home/petalinux/.ssh/id_dropbear_rsa -r \
  /home/petalinux/Projects/kria-kv260-starter/scripts/windows/* \
  <windows-ssh-user>@<windows-ip>:C:/Users/<windows-user>/Projects/petalinux/kv260-remote-gui/
```

Then run the installer on Windows:

```sh
ssh -i /home/petalinux/.ssh/id_dropbear_rsa -y <windows-ssh-user>@<windows-ip> \
  'powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\<windows-user>\Projects\petalinux\kv260-remote-gui\Install-KV260WindowsShortcuts.ps1 -HostAlias petalinux-kv260'
```

## Verification Commands

Check that Windows can reach the board alias:

```sh
ssh -i /home/petalinux/.ssh/id_dropbear_rsa -y <windows-ssh-user>@<windows-ip> \
  'powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\<windows-user>\Projects\petalinux\kv260-remote-gui\Open-KV260EventCamera.ps1 -HostAlias petalinux-kv260 -CheckOnly'
```

Expected output includes:

```text
SSH=C:\WINDOWS\System32\OpenSSH\ssh.exe
BOARD_SCRIPT=...
X11_SCRIPT=...
board-desktop: stopped
windows-x11: stopped
```

Check Windows X11 prerequisites:

```sh
ssh -i /home/petalinux/.ssh/id_dropbear_rsa -y <windows-ssh-user>@<windows-ip> \
  'powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\<windows-user>\Projects\petalinux\kv260-remote-gui\Start-KV260EventCamera-X11.ps1 -HostAlias petalinux-kv260 -CheckOnly'
```

Expected output on the current Windows machine:

```text
VCXSRV=C:\Program Files\VcXsrv\vcxsrv.exe
SSH=C:\WINDOWS\System32\OpenSSH\ssh.exe
REMOTE=cd /home/petalinux/Projects/kria-kv260-starter && ./scripts/kv260-event-camera-switch.sh --x11
```

Check board-side status directly:

```sh
cd /home/petalinux/Projects/kria-kv260-starter
./scripts/kv260-event-camera-switch.sh --status
```

## Runtime Logs

Board HDMI app log:

```text
/home/petalinux/.cache/kv260-event-camera/app.log
```

Board SSH-X11 app log:

```text
/home/petalinux/.cache/kv260-event-camera/x11-forward.log
```

Windows launcher logs:

```text
%TEMP%\kv260-event-camera\board-desktop-launch.log
%TEMP%\kv260-event-camera\windows-x11-launch.log
```

## Practical Recommendation

Use the single `KV260 Event Camera` Windows shortcut. Choose `Open On Windows` when you want the app on Windows, or `Open On KV260 Display` when you want the app on the board monitor. Switching modes is allowed; the switcher stops the previous mode first.

RDP is not required for either path.

## Confirmed Good Workflow

Verified on 2026-06-01:

- The single Windows entrance shortcut `KV260 Event Camera.lnk` opens the control panel correctly.
- The panel buttons work as the preferred workflow.
- `Open On Windows` is the correct path when the GUI should appear on the Windows desktop through SSH X11.
- `Open On KV260 Display` is the correct path when the GUI should appear on the board HDMI display.
- The old two-shortcut design is intentionally retired because it was too easy to leave `/dev/video0` owned by the other display mode.

Future launcher changes should preserve this single-entry design unless there is a strong reason to split the workflow again.
