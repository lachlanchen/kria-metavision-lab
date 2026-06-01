#!/bin/sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="${KV260_EVENT_VISUAL_DIR:-$PROJECT_DIR/recordings/event-visual}"
LOG_LOOP="$DATA_DIR/loop.log"
LOG_SESSION="$DATA_DIR/session.log"
MAX_FILES="${KV260_EVENT_VISUAL_MAX_FILES:-20}"
mkdir -p "$DATA_DIR"

pick_device() {
  if [ -e /dev/video0 ]; then
    echo /dev/video0
    return
  fi
  if [ -e /dev/video1 ]; then
    echo /dev/video1
    return
  fi
  for v in /dev/video*; do
    [ -e "$v" ] || continue
    echo "$v"
    return
  done
}

DEVICE="$(pick_device)"
if [ -z "$DEVICE" ]; then
  echo "no video device found" >> "$LOG_LOOP"
  exit 1
fi

i=1
while true; do
  ts="$(date +%Y%m%d_%H%M%S)"
  out="$DATA_DIR/event-${ts}-${i}.raw"

  if /usr/bin/v4l2-ctl -d "$DEVICE" --stream-mmap --stream-count=200 --stream-to="$out" >>"$LOG_LOOP" 2>&1; then
    size="$(stat -c %s "$out" 2>/dev/null || echo 0)"
    printf "captured %s device=%s bytes=%s file=%s\n" "$ts" "$DEVICE" "$size" "$out" | tee -a "$LOG_SESSION"
  else
    echo "capture-fail $(date) device=$DEVICE" | tee -a "$LOG_SESSION"
    sleep 1
  fi

  i=$((i + 1))
  count="$(ls -1 "$DATA_DIR"/event-*.raw 2>/dev/null | wc -l)"
  if [ "$count" -gt "$MAX_FILES" ]; then
    remove_count=$((count - MAX_FILES))
    ls -1tr "$DATA_DIR"/event-*.raw 2>/dev/null | head -n "$remove_count" | xargs -r rm -f
  fi
  sleep 0.2
done
