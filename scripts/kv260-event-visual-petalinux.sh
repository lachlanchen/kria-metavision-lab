#!/usr/bin/env sh
set -eu

BOARD_IP="${KV260_BOARD_IP:-}"
SSH_USER="petalinux"
VIDEO_DEV="/dev/video0"
ACTION="attach"

usage() {
  cat <<'EOF'
Usage:
  kv260-event-visual-petalinux.sh [--board IP] [--user USER] [--video /dev/videoX] [--start|--attach|--status|--stop]

Actions:
  --start   Create or re-use an event-visual tmux session in the chosen user account.
  --attach  Attach to the existing event-visual tmux session (default).
  --status  Show tmux session + latest stream log lines.
  --stop    Stop the event-visual tmux session.

Defaults:
  --board  <kv260-ip> or KV260_BOARD_IP
  --user   petalinux
  --video  /dev/video0
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --board)
      BOARD_IP="$2"
      shift 2
      ;;
    --user)
      SSH_USER="$2"
      shift 2
      ;;
    --video)
      VIDEO_DEV="$2"
      shift 2
      ;;
    --start|--attach|--status|--stop)
      ACTION="$1"
      shift
      ;;
    -h|--help)
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

if [ -z "${BOARD_IP}" ]; then
  echo "Missing board address. Pass --board <kv260-ip> or set KV260_BOARD_IP." >&2
  exit 1
fi

ssh \
  "LC_ALL=en_GB.UTF-8 LC_CTYPE=en_GB.UTF-8 LANG=en_GB.UTF-8 ACTION='${ACTION}' VIDEO_DEV='${VIDEO_DEV}' sh -s" \
  "${SSH_USER}@${BOARD_IP}" <<'REMOTE'
set -eu

ACTION="${ACTION}"
VIDEO_DEV="${VIDEO_DEV}"
SESSION="event-visual"
TMUX_NAME="kv260-event-visual"
TMUX="tmux -L ${TMUX_NAME}"

mkdir -p /tmp/event-visual

cat > /tmp/event-visual-acquire.sh <<EOS
#!/bin/sh
set -eu

VIDEO_DEV="${VIDEO_DEV}"
LOG_LOOP="/tmp/event-visual-loop.log"

mkdir -p /tmp/event-visual

while true; do
  TS="\$(date +%Y%m%d-%H%M%S)"
  RAW="/tmp/event-visual/\${TS}.raw"

  /usr/bin/v4l2-ctl -d "\${VIDEO_DEV}" \\
    --stream-count=10 \\
    --stream-mmap \\
    --stream-to="\${RAW}" >> "\${LOG_LOOP}" 2>&1 || true

  if [ -s "\${RAW}" ]; then
    SIZE="\$(wc -c < "\${RAW}")"
    echo "\$(date -Iseconds) ok size=\${SIZE}B file=\${RAW}" >> "/tmp/event-visual-session.log"
  else
    rm -f "\${RAW}" || true
    echo "\$(date -Iseconds) empty/failed stream from \${VIDEO_DEV}" >> "/tmp/event-visual-session.log"
  fi
done
EOS

chmod +x /tmp/event-visual-acquire.sh

if [ "${ACTION}" = "--start" ]; then
  if "${TMUX}" has-session -t "${SESSION}" 2>/dev/null; then
    echo "Session already exists: ${SESSION}"
  else
    "${TMUX}" new-session -d -s "${SESSION}" "/bin/sh /tmp/event-visual-acquire.sh"
    echo "Started session: ${SESSION}"
  fi
  exit 0
fi

if [ "${ACTION}" = "--status" ]; then
  "${TMUX}" ls || true
  if [ -f /tmp/event-visual-loop.log ]; then
    echo "--- latest stream samples ---"
    tail -n 20 /tmp/event-visual-loop.log
  fi
  if [ -f /tmp/event-visual-session.log ]; then
    echo "--- latest session status ---"
    tail -n 20 /tmp/event-visual-session.log
  fi
  exit 0
fi

if [ "${ACTION}" = "--stop" ]; then
  "${TMUX}" kill-session -t "${SESSION}" 2>/dev/null || true
  echo "Stopped session: ${SESSION}"
  exit 0
fi

if ! "${TMUX}" has-session -t "${SESSION}" 2>/dev/null; then
  echo "No session '${SESSION}'. Run --start first."
  exit 1
fi

"${TMUX}" attach -t "${SESSION}"
REMOTE
