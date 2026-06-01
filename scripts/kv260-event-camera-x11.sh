#!/usr/bin/env sh
set -eu

WORKDIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="${KV260_EVENT_CAMERA_X11_LOG:-${HOME:-/home/petalinux}/.cache/kv260-event-camera/x11-forward.log}"
APP_LOCK="${KV260_EVENT_CAMERA_APP_LOCK_PATH:-/tmp/kv260-event-camera-app-x11.lock}"
APP_SOCKET="${KV260_EVENT_CAMERA_APP_SOCKET:-/tmp/kv260-event-camera-app-x11.sock}"

if [ -z "${DISPLAY:-}" ]; then
  echo "DISPLAY is not set. Connect from Windows with SSH X forwarding, for example: ssh -Y petalinux-kv260" >&2
  exit 2
fi

mkdir -p "$(dirname "${LOG_FILE}")" 2>/dev/null || true
touch "${LOG_FILE}" 2>/dev/null || true

export HOME="${HOME:-/home/petalinux}"
export USER="${USER:-petalinux}"
export LOGNAME="${LOGNAME:-${USER}}"
export LANG=C
export LC_ALL=C
export NO_AT_BRIDGE=1
export KV260_EVENT_CAMERA_APP_LOCK_PATH="${APP_LOCK}"
export KV260_EVENT_CAMERA_APP_SOCKET="${APP_SOCKET}"
export KV260_EVENT_CAMERA_APP_LOG_FILE="${LOG_FILE}"

if [ -S "${APP_SOCKET}" ]; then
  if python3 - "${APP_SOCKET}" >> "${LOG_FILE}" 2>&1 <<'PY'
import socket
import sys

sock_path = sys.argv[1]
try:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(0.8)
        client.connect(sock_path)
        client.sendall(b"present")
except OSError:
    raise SystemExit(1)
PY
  then
    echo "Requested existing SSH-X11 KV260 Event Camera window to present." >> "${LOG_FILE}" 2>&1
    exit 0
  fi
fi

exec python3 "${WORKDIR}/kv260-event-camera-app.py" >> "${LOG_FILE}" 2>&1
