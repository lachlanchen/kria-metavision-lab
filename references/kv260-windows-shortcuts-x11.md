# KV260 Windows Launcher And SSH X11

Generated: 2026-05-31

## Goal

Provide one Windows entry point for the custom `KV260 Event Camera` GUI, common board GUI applications, Jupyter Notebook, and board power actions while keeping the normal KV260 HDMI desktop launcher working.

The installed Windows shortcut is:

```text
KV260 Control Center
```

It opens a control panel with these tabs:

| Tab | Result |
| --- | --- |
| `Camera` | Custom event-camera GUI on Windows or the board display, native Metavision viewer, stop, and status. |
| `Applications` | PCManFM, Matchbox Terminal, RXVT Terminal, L3afpad, Appearance, touchscreen calibration, preferred apps, and desktop preferences through SSH X11. |
| `Notebook And Power` | Jupyter Notebook through an SSH tunnel, Jupyter stop, reboot, and shutdown. |

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

Generic board GUI app mapper:

```text
scripts/kv260-remote-gui-app.sh
```

Jupyter server manager:

```text
scripts/kv260-jupyter-notebook.sh
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
%USERPROFILE%\Desktop\KV260 Control Center.lnk
%APPDATA%\Microsoft\Windows\Start Menu\Programs\KV260\KV260 Control Center.lnk
```

Windows does not provide a reliable supported command-line API for silently pinning arbitrary shortcuts to the taskbar. Use the Start Menu `KV260` folder, then right-click the shortcut and choose `Pin to taskbar`.

The installer also writes the custom shortcut icon:

```text
%USERPROFILE%\Projects\petalinux\kv260-remote-gui\kv260-control-center.ico
```

The older direct shortcuts are intentionally removed from the Desktop by the installer:

```text
KV260 Event Camera.lnk
KV260 Event Camera - Board Desktop.lnk
KV260 Event Camera - Windows X11.lnk
KV260 Viewer - Open.lnk
KV260 Viewer - Close.lnk
kv260-viewer.lnk
```

Their PowerShell scripts remain available under `%USERPROFILE%\Projects\petalinux\kv260-remote-gui` for debugging, but the normal workflow is the single `KV260 Control Center` shortcut.

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

Board Jupyter log:

```text
/home/petalinux/.cache/kv260-event-camera/jupyter-notebook.log
```

Windows launcher logs:

```text
%TEMP%\kv260-event-camera\board-desktop-launch.log
%TEMP%\kv260-event-camera\windows-x11-launch.log
%TEMP%\kv260-event-camera\x11-app-<app-id>.log
```

## Practical Recommendation

Use the single `KV260 Control Center` Windows shortcut. Choose `Open Camera On Windows` when you want the camera app on Windows, or `Open Camera On KV260` when you want the app on the board monitor. Switching camera modes is allowed; the switcher stops the previous mode first.

Use the `Applications` tab for non-camera board GUI apps. Those apps open directly on Windows through SSH X11 and do not require RDP.

Use `Open Jupyter Notebook` instead of the old Jupyter desktop entry. The desktop entry tries to behave like a local browser app; the control center starts the board-side notebook server, opens an SSH tunnel to `127.0.0.1:8888`, and opens the Windows browser.

RDP is not required for either path.

## Confirmed Good Workflow

Verified on 2026-06-01:

- The single Windows entrance shortcut `KV260 Control Center.lnk` opens the control panel correctly.
- The camera panel buttons work as the preferred workflow.
- `Open Camera On Windows` is the correct path when the camera GUI should appear on the Windows desktop through SSH X11.
- `Open Camera On KV260` is the correct path when the camera GUI should appear on the board HDMI display.
- The `Applications` tab exposes the common board GUI apps through SSH X11.
- Jupyter start/stop works through `scripts/kv260-jupyter-notebook.sh`; the Windows control center opens it through an SSH tunnel.
- The old two-shortcut design is intentionally retired because it was too easy to leave `/dev/video0` owned by the other display mode.

Future launcher changes should preserve this single-entry design unless there is a strong reason to split the workflow again.
