# Windows SSH X11 to KV260 (<kv260-ip>)

## Goal

Run `metavision_viewer` on the KV260 board display from Windows <windows-ip> using SSH X forwarding (not RDP).

## Board prerequisites (<kv260-ip>)

- SSH daemon is Dropbear (`dropbear`) and listening on port `22`.
- GUI stack is present and functional on-board (`Xorg :0` + `matchbox` for local monitor use).

## Windows prerequisites (<windows-ip>)

- Run an X server:
  - VcXsrv (recommended), or
  - MobaXterm (X server is built in).
- Confirm your SSH client is available:
  - PowerShell: `ssh`
  - or PuTTY session with X11 forwarding enabled.

## OpenSSH client flow (recommended)

1. Start VcXsrv with default local display (`localhost:0`).
2. Open PowerShell:

```powershell
ssh -X petalinux@<kv260-ip>
```

3. If prompted, authenticate and verify you are on the board.
4. On the KV260 shell:

```bash
echo "$DISPLAY"
metavision_viewer
```

`DISPLAY` should look like `localhost:10.0` (or similar) for forwarded X.

## PuTTY flow

- In PuTTY: **Connection → SSH → X11**
  - Check **Enable X11 forwarding**
  - (Optional) Set x11 display to `localhost:0`.
- Connect as `petalinux@<kv260-ip>`.
- Run `metavision_viewer` from the shell.

## Notes

- This workflow is independent from RDP/VNC and uses a Windows X server.
- It avoids the `xrdp` package dependency; the current local feed does not provide `xrdp/xorgxrdp` packages for an RDP listener.
- If forwarding is blocked, check:
  - VcXsrv access control / firewall,
  - Windows client `DISPLAY` assignment,
  - Dropbear service running on board.

## Quick status checks from board

```bash
# confirm SSH listener
ps -ef | grep -E "dropbear" | grep -v grep

# confirm no RDP listener is currently expected
ss -ltnp | grep 3389 || echo "No 3389 listener"

# confirm board X server
ls -l /tmp/.X11-unix/X0
```

## Reference

- `references/kv260-rdp-research.md` (why RDP is optional for this workflow),
- `references/kv260-event-visual-gui-launch.md` (local GUI launch notes),
- `references/windows-ssh-key-auth.md` (if you need key auth to/from <windows-ip>).
