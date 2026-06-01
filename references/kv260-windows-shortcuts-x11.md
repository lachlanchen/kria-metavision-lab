# KV260 Windows Shortcuts And SSH X11 Launch

Generated: 2026-05-31

## Goal

Provide one-click access to the custom `KV260 Event Camera` GUI from Windows while keeping the normal KV260 HDMI desktop launcher working.

There are now two Windows launch modes:

| Shortcut | Result |
| --- | --- |
| `KV260 Event Camera - Board Desktop` | Uses Windows SSH to ask the KV260 to open or raise the app on the board HDMI desktop (`DISPLAY=:0`). |
| `KV260 Event Camera - Windows X11` | Starts VcXsrv on Windows if needed, opens an SSH X11 session, and shows the app window on Windows. |

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

## Single-Window Behavior

The app has a small Unix socket command channel. Re-running the same launcher does not create duplicate windows:

- if the app is already open, the launcher sends `present`;
- if it is not open, the launcher starts it;
- `Close Camera` releases `/dev/video0`;
- `Quit` exits the GUI.

The HDMI app and the SSH-X11 app use separate lock/socket files, but the camera hardware is still exclusive. Only one process can own `/dev/video0` at a time. If the HDMI app is already streaming, close it before using the Windows X11 shortcut for live events.

## Windows Files Installed

The Windows-side scripts are staged here:

```text
%USERPROFILE%\Projects\petalinux\kv260-remote-gui
```

Installed shortcuts:

```text
%USERPROFILE%\Desktop\KV260 Event Camera - Board Desktop.lnk
%USERPROFILE%\Desktop\KV260 Event Camera - Windows X11.lnk
%APPDATA%\Microsoft\Windows\Start Menu\Programs\KV260\KV260 Event Camera - Board Desktop.lnk
%APPDATA%\Microsoft\Windows\Start Menu\Programs\KV260\KV260 Event Camera - Windows X11.lnk
```

Windows does not provide a reliable supported command-line API for silently pinning arbitrary shortcuts to the taskbar. Use the Start Menu `KV260` folder, then right-click the shortcut and choose `Pin to taskbar`.

## Windows Prerequisites

Verified on Windows:

```text
OpenSSH client: C:\WINDOWS\System32\OpenSSH\ssh.exe
VcXsrv: C:\Program Files\VcXsrv\vcxsrv.exe
Windows sshd service: Running, Automatic
```

`VcXsrv` is only needed for the `Windows X11` shortcut. The `Board Desktop` shortcut does not need a Windows X server because the window appears on the KV260 HDMI desktop.

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
  'powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\<windows-user>\Projects\petalinux\kv260-remote-gui\Start-KV260EventCamera-BoardDesktop.ps1 -HostAlias petalinux-kv260 -CheckOnly'
```

Expected output:

```text
kv260-board-ok
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
REMOTE=cd /home/petalinux/Projects/kria-kv260-starter && ./scripts/kv260-event-camera-x11.sh
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

Use `KV260 Event Camera - Board Desktop` for the most stable workflow when sitting at the KV260 display. Use `KV260 Event Camera - Windows X11` when you want the app window on Windows and VcXsrv is running.

RDP is not required for either path.
