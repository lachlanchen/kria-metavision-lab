#!/usr/bin/env sh
set -eu

MODE="all"
LOG_FILE="/tmp/kv260-camera-deep-scan.log"
OUT_FILE="${OUT_FILE:-/tmp/kv260-camera-deep-scan.txt}"

usage() {
  cat <<'EOF'
Usage:
  kv260-camera-deep-scan.sh [--quick|--full|--help]

Modes:
  --quick   Basic device enumeration only.
  --full    Run full transport checks (USB/I2C/media/v4l2 + kernel logs).
  --help    Show help.

Environment:
  LOG_FILE  Log file path (default: /tmp/kv260-camera-deep-scan.log)
  OUT_FILE  Report file path (default: /tmp/kv260-camera-deep-scan.txt)
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --quick)
      MODE="quick"
      shift
      ;;
    --full)
      MODE="full"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

echo_block() {
  printf '\n===== %s =====\n' "$1"
}

log() {
  printf '%s\n' "$1"
}

scan_v4l2() {
  echo_block "V4L2 video devices"
  found=0
  for dev in /dev/video*; do
    [ -e "$dev" ] || continue
    found=1
    fmt="unknown"
    driver="unknown"
    if has_cmd v4l2-ctl; then
      fmt="$(v4l2-ctl -d "$dev" --all 2>/dev/null \
        | awk -F"'" '/Pixel Format/ { print $2; exit }')"
      driver="$(v4l2-ctl -d "$dev" --all 2>/dev/null \
        | sed -n '/Driver name/ { s/.*:[[:space:]]*//; p; q }')"
    fi
    node="${fmt:-unknown}"
    kind="frame"
    case "$node" in
      *PSE*|*pse*|*PSEE*)
        kind="event"
        ;;
    esac
    log "  $dev  kind=$kind  driver=${driver:-unknown}  fmt=${node:-unknown}"
  done
  [ "$found" -eq 0 ] && log "  (none)"
}

scan_media() {
  echo_block "Media graph"
  found=0
  for media in /dev/media*; do
    [ -e "$media" ] || continue
    found=1
    log "  $media"
    if has_cmd media-ctl; then
      log "    media-ctl -d $media -p:"
      media-ctl -d "$media" -p 2>/dev/null | sed 's/^/    /' | sed -n '1,160p'
    else
      log "    media-ctl not available"
    fi
  done
  [ "$found" -eq 0 ] && log "  (none)"
}

scan_usb() {
  echo_block "USB devices"
  if has_cmd lsusb; then
    lsusb 2>/dev/null | sed 's/^/  /'
  else
    log "  lsusb not available"
  fi
}

scan_i2c() {
  echo_block "I2C bus scan"
  if ! has_cmd i2cdetect; then
    log "  i2cdetect not available"
    return
  fi
  for bus in /dev/i2c-*; do
    [ -e "$bus" ] || continue
    busnum="${bus##*/i2c-}"
    log "  /dev/i2c-${busnum}"
    i2cdetect -y "$busnum" 2>/dev/null | sed 's/^/    /' | sed -n '1,220p' || true
  done
}

scan_firmware() {
  echo_block "Kernel modules + firmware overlays"
  if has_cmd lsmod; then
    for mod in psee_video imx636 genx320 ps_host_if uvcvideo v4l2loopback; do
      if lsmod | awk '{print $1}' | grep -qx "$mod"; then
        log "  module: $mod loaded"
      fi
    done
  fi
  if [ -d /lib/firmware/xilinx ]; then
    log "  firmware overlays in /lib/firmware/xilinx:"
    ls /lib/firmware/xilinx/*.dtbo 2>/dev/null | sed 's/^/    /' || true
  else
    log "  /lib/firmware/xilinx missing"
  fi
}

scan_kernel() {
  echo_block "Kernel messages (camera-related, latest)"
  if has_cmd dmesg; then
    dmesg | grep -Ei "video|v4l|csi|mipi|sensor|ias|uvc|ps_host_if|psee|imx636" \
      | tail -n 120 | sed 's/^/  /' || log "  no matching lines"
  else
    log "  dmesg not available"
  fi
}

scan_sysfs() {
  echo_block "Camera-related sysfs nodes"
  if [ -d /dev/v4l ]; then
    ls -la /dev/v4l* 2>/dev/null | sed 's/^/  /'
  fi
  if [ -d /sys/class/video4linux ]; then
    log "  /sys/class/video4linux:"
    ls /sys/class/video4linux | sed 's/^/    /'
  fi
}

scan_fast_recommendation() {
  echo_block "Recommended interpretation"
  cat <<'EOF'
Recommendations:
- If all /dev/video* are PSE format, Prophesee event overlay is dominating camera exposure.
- A normal frame camera on J8 is only exposed as non-PSE video when its own sensor overlay/driver is present.
- If you only see one camera node, test frame-only mode on each candidate node:
    ./kv260-camera-viewer.sh --type frame --start --video /dev/videoN
  (replace N from 0..9).
- If the camera is frame and you need both paths, you need a dual-path FPGA/kernel design and matching drivers.
EOF
}

{
  printf '[%s] kv260-camera-deep-scan mode=%s\n' "$(date -Iseconds)" "$MODE"
  scan_v4l2
  scan_media
  scan_usb
  if [ "${MODE}" = "full" ]; then
    scan_i2c
    scan_sysfs
    scan_firmware
    scan_kernel
  fi
  scan_fast_recommendation
} | tee "$LOG_FILE" > "$OUT_FILE"

log "Saved report:"
log "  LOG:  $LOG_FILE"
log "  OUT:  $OUT_FILE"
