#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET_USER="${KV260_DESKTOP_USER:-petalinux}"
APP_SOCKET="${KV260_EVENT_CAMERA_APP_SOCKET:-/tmp/kv260-event-camera-app.sock}"
HELPER="${PROJECT_DIR}/scripts/kv260-event-visual-gui-local.sh"

resolve_home() {
  if command -v getent >/dev/null 2>&1; then
    home_guess="$(getent passwd "${TARGET_USER}" | awk -F: '{print $6}' 2>/dev/null || true)"
  else
    home_guess="$(awk -F: -v user="${TARGET_USER}" '$1==user {print $6; exit}' /etc/passwd 2>/dev/null || true)"
  fi
  if [ -z "${home_guess}" ] || [ ! -d "${home_guess}" ]; then
    home_guess="/home/${TARGET_USER}"
  fi
  printf '%s\n' "${home_guess}"
}

normalize_display() {
  raw="${1:-:0}"
  if printf '%s' "${raw}" | grep -q ":"; then
    display_num="${raw##*:}"
  else
    display_num="${raw#:}"
  fi
  display_num="${display_num%.0}"
  case "${display_num}" in
    ''|*[!0-9]*) display_num=0 ;;
  esac
  DISPLAY=":${display_num}"
  export DISPLAY
}

viewer_pids() {
  ps -e -o pid= -o comm= 2>/dev/null | awk '$2 == "metavision_view" || $2 == "metavision_viewer" { print $1 }'
}

app_pids() {
  ps -e -o pid= -o args= 2>/dev/null | awk '/kv260-event-camera-app[.]py/ { print $1 }'
}

log() {
  printf '%s %s\n' "$(date -Iseconds)" "$*" >> "${LOG_FILE}"
}

close_custom_app() {
  if [ -S "${APP_SOCKET}" ]; then
    python3 - "${APP_SOCKET}" >> "${LOG_FILE}" 2>&1 <<'PY' || true
import socket
import sys

sock_path = sys.argv[1]
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
    client.settimeout(0.8)
    client.connect(sock_path)
    client.sendall(b"quit")
PY
  fi

  tries=0
  while [ "${tries}" -lt 5 ]; do
    if [ -z "$(app_pids | head -n 1)" ]; then
      return 0
    fi
    sleep 0.5
    tries=$((tries + 1))
  done

  for pid in $(app_pids); do
    kill "${pid}" 2>/dev/null || true
  done
}

TARGET_HOME="$(resolve_home)"
if [ -z "${HOME:-}" ] || [ ! -d "${HOME}" ]; then
  HOME="${TARGET_HOME}"
fi
export HOME USER="${TARGET_USER}" LOGNAME="${TARGET_USER}" LANG=C LC_ALL=C NO_AT_BRIDGE=1
normalize_display "${DISPLAY:-:0}"
XAUTHORITY="${XAUTHORITY:-${HOME}/.Xauthority}"
if [ ! -r "${XAUTHORITY}" ] && [ -r /home/petalinux/.Xauthority ]; then
  XAUTHORITY="/home/petalinux/.Xauthority"
fi
if [ ! -r "${XAUTHORITY}" ] && [ -r /root/.Xauthority ]; then
  XAUTHORITY="/root/.Xauthority"
fi
export XAUTHORITY

RUNTIME_DIR="${XDG_RUNTIME_DIR:-${HOME}/.cache/kv260-event-viewer}"
if [ -z "${RUNTIME_DIR}" ] || [ "${RUNTIME_DIR}" = "/tmp" ] || [ "${RUNTIME_DIR}" = "/tmp/" ]; then
  RUNTIME_DIR="${HOME}/.cache/kv260-event-viewer"
fi
mkdir -p "${RUNTIME_DIR}"
chmod 700 "${RUNTIME_DIR}" 2>/dev/null || true
LOG_FILE="${RUNTIME_DIR}/metavision-toggle.log"
: >> "${LOG_FILE}"

if [ -n "$(viewer_pids | head -n 1)" ]; then
  log "Metavision viewer running; closing it."
  "${HELPER}" --stop --force --display "${DISPLAY}" >> "${LOG_FILE}" 2>&1 || true
  exit 0
fi

log "Metavision viewer not running; opening it."
close_custom_app
"${HELPER}" --start --force --low-latency --no-record --no-rearm --display "${DISPLAY}" >> "${LOG_FILE}" 2>&1 || {
  log "First start failed; retrying with recovery rearm."
  "${HELPER}" --start --force --low-latency --no-record --rearm --display "${DISPLAY}" >> "${LOG_FILE}" 2>&1 || true
}

exit 0
