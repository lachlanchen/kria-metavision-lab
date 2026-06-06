# Topology Reference

Use this when identifying machines, paths, and roles.

## Current LAN

```text
KV260 hostname: xilinx-kv260-starterkit-20222
KV260 IP:       192.168.1.250
KV260 user:     petalinux
KV260 repo:     /home/petalinux/Projects/kria-kv260-starter

Windows host:   CSG1175-P
Windows IP:     192.168.1.166
Windows user:   Administrator
Projects root:  C:\Users\Administrator\Projects
```

## Roles

```text
KV260
  Prophesee event camera
  /dev/video0
  /dev/v4l-subdev3 biases
  event recording API

Windows
  Arduino over USB serial
  arduino-cli
  future Arduino control API
  four related research repos

Arduino UNO
  no IP address
  USB serial device behind Windows
  previous port: COM3
  current problem noted by Windows: only COM1 Unknown detected
```

## Reachability

From KV260:

```sh
ping -c 2 192.168.1.166
ssh -i /home/petalinux/.ssh/id_dropbear_rsa -y Administrator@192.168.1.166 "powershell -NoProfile -Command \"hostname\""
```

The board Dropbear SSH client may ignore OpenSSH options such as `BatchMode=yes` or `ConnectTimeout=8`.

## Recommended Service Ports

```text
KV260 event recording API:   192.168.1.250:8765
Windows Arduino control API: 192.168.1.166:8780
```

Do not use hostnames as the primary path unless name resolution is explicitly verified. Use IPs.

## Source Docs

```text
/home/petalinux/Projects/kria-kv260-starter/references/kv260-windows-arduino-situation.md
/home/petalinux/Projects/kria-kv260-starter/references/windows-arduino-codex-handoff.md
```
