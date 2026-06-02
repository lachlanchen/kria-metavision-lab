# KV260 File Transfer GUI

Updated: 2026-06-01

This repo now has two file-transfer entry points:

- Windows native: `KV260 Control Center -> Files`
- Board native / SSH-X: `scripts/kv260-file-transfer-gui.sh`

The design is intentionally simple and robust. It uses OpenSSH `ssh` and `scp` instead of SFTP, because the current PetaLinux image does not provide an SFTP server.

## Design

There are two frontends instead of one overloaded app:

| Frontend | Runs on | Main use |
| --- | --- | --- |
| Windows Control Center Files tab | Windows | Fast Windows-to-KV260 and KV260-to-Windows copies using the existing board SSH alias |
| `KV260 File Transfer` GTK app | KV260 desktop or SSH X11 | Board-to-remote-host copies where the remote host can be Windows, Linux, or macOS |

This keeps the Windows experience native and keeps the board experience usable even when no Windows machine is involved.

Both frontends use the same visual direction:

```text
left  = KV260 board
right = remote host / Windows
```

## Windows Control Center Files Tab

Capabilities:

- two-pane file browser,
- left pane: KV260 filesystem,
- right pane: Windows local filesystem,
- folder and common file-type icons in the file lists,
- multi-select upload and download,
- drag selected Windows rows onto the KV260 pane to upload,
- drag selected KV260 rows onto the Windows pane to download,
- drag files from Windows Explorer onto the KV260 pane to upload,
- drag onto empty pane space to copy into the current folder,
- drag onto a folder row/icon to copy directly into that folder,
- create a new folder on the KV260,
- open the board-side transfer GUI through SSH X11.

The Windows side uses:

```powershell
ssh.exe <board-alias> ...
scp.exe -O -r ...
```

`-O` is required because this PetaLinux image does not have an SFTP server.

## Board-Side GTK File Transfer

Launch locally on the KV260:

```sh
cd ~/Projects/kria-kv260-starter
./scripts/kv260-file-transfer-gui.sh
```

Launch through SSH X11 from Windows/macOS/Linux:

```sh
ssh -Y petalinux-kv260 'cd /home/petalinux/Projects/kria-kv260-starter && ./scripts/kv260-file-transfer-gui.sh'
```

The board-side app stores its connection settings here:

```text
~/.config/kv260-file-transfer.json
```

Default remote settings are tuned for the Windows machine used during bring-up:

```text
Administrator@192.168.1.166
C:/Users/Administrator/Projects/petalinux
~/.ssh/id_dropbear_rsa
```

You can change these in the top row of the app.

## Password And Key Behavior

Recommended:

```text
SSH key auth
```

Password auth is supported by the board-side app only when `sshpass` is installed. The full setup script now tries to install `sshpass` best-effort, but some PetaLinux feeds may not include it.

If `sshpass` is missing, use a key instead.

## Setup Script

Full setup:

```sh
KV260_SUDO_PASSWORD=<password> ./scripts/kv260-full-setup.sh
```

The setup path:

- installs the board launcher,
- exposes the transfer GUI through `kv260-remote-gui-app.sh`,
- copies the updated Windows control center when Windows LAN SSH options are provided,
- best-effort installs OpenSSH SCP and `sshpass`.

Windows control center deployment:

```sh
KV260_SUDO_PASSWORD=<password> ./scripts/kv260-full-setup.sh \
  --windows-host 192.168.1.166 \
  --windows-user Administrator \
  --windows-key /home/petalinux/.ssh/id_dropbear_rsa \
  --windows-board-alias petalinux-kv260
```

## Notes

- Transfers are synchronous. Large folders will keep the UI busy until `scp` finishes.
- Keep paths simple when possible. Spaces are handled in the Windows control center for board paths, but legacy SCP quoting is still less forgiving than modern SFTP.
- For very large datasets, direct command-line `scp -O -r` is still the most predictable path.

## Validation Performed

On 2026-06-01:

- Deployed the updated Windows control center to `192.168.1.166`.
- Ran `Open-KV260EventCamera.ps1 -CheckOnly` on Windows; it found both `ssh.exe` and `scp.exe`.
- Tested Windows -> KV260 -> Windows round-trip with `scp.exe -O`.
- Tested board -> Windows -> board round-trip with the board-side transfer engine.
- Tested board-side Windows directory listing through PowerShell JSON over SSH.
- Installed the board desktop launcher:

```text
/usr/share/applications/kv260-file-transfer.desktop
```

Update after layout/debug pass:

- Windows Control Center Files tab was changed to show KV260 on the left and Windows on the right.
- Top path controls were spaced wider so Browse/Up buttons do not overlap the path boxes.
- Board-side GTK app was changed to capture background-thread exceptions safely, avoiding delayed GTK callback tracebacks.
- Re-ran Windows `-CheckOnly`, board-side Windows directory listing, Windows -> KV260 -> Windows transfer, and board -> Windows -> board transfer after the fix.

Update after Windows popup traceback fix:

- Added `scripts/kv260-list-files-json.py` as the board-side JSON directory listing helper.
- The Windows Control Center no longer sends inline multi-line Python through SSH for board file listing.
- The Windows Control Center avoids PowerShell nested `ssh.exe` output capture, which can hang or surface truncated traceback popups in this setup.
- Board listing now writes command output to temporary files on the KV260, pulls those files with `scp -O`, parses the JSON locally, and cleans up the temporary files.
- Re-ran deployed Windows `-FilesSelfTest`; it listed `/home/petalinux/Projects/kria-kv260-starter` successfully.

Update after icon/drop-target pass:

- Windows Control Center Files tab now uses colored icons for folders and common file classes: text, code, image, video, audio, archives, PDF, Office, tables, and capture/raw files.
- Folder rows are styled more strongly and show their full path as a tooltip.
- Drag-and-drop is destination-aware: dropping onto empty pane space copies into the current folder, while dropping onto a folder row/icon copies directly into that folder.

Update after drag feedback pass:

- Dragging over a valid pane now gives immediate visual feedback.
- The target pane changes to a subtle active background while a compatible item is dragged over it.
- Folder rows highlight when they are the active drop target.
- A hint line in the Files tab shows the current destination folder while dragging.

Update after Control Center visual polish pass:

- Action buttons now use drawn icons and hover/down colors.
- Camera, Applications, Files, Notebook, and Power controls have icon-specific buttons.
- The header now has a compact KV260 visual mark instead of plain text only.
- Added `-UiSelfTest` to validate the icon/button factory without opening the full window.
