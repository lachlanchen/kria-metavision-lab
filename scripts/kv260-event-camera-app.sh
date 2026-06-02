#!/usr/bin/env sh
set -eu

WORKDIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_USER="${KV260_DESKTOP_USER:-petalinux}"
LOG_FILE_OVERRIDE="${KV260_EVENT_CAMERA_APP_LOG:-}"
APP_SOCKET="${KV260_EVENT_CAMERA_APP_SOCKET:-/tmp/kv260-event-camera-app.sock}"
APP_LOCK="${KV260_EVENT_CAMERA_APP_LOCK_PATH:-/tmp/kv260-event-camera-app.lock}"
FOREGROUND="${KV260_EVENT_CAMERA_APP_FOREGROUND:-0}"

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

TARGET_HOME="$(resolve_home)"
export HOME="${TARGET_HOME}"
export USER="${TARGET_USER}"
export LOGNAME="${TARGET_USER}"
export LANG=C
export LC_ALL=C
export PYTHONIOENCODING="${PYTHONIOENCODING:-utf-8}"
export NO_AT_BRIDGE=1
export KV260_EVENT_CAMERA_APP_SOCKET="${APP_SOCKET}"
export KV260_EVENT_CAMERA_APP_LOCK_PATH="${APP_LOCK}"
LOG_FILE="${LOG_FILE_OVERRIDE:-${HOME}/.cache/kv260-event-camera/app.log}"
export XAUTHORITY="${XAUTHORITY:-${HOME}/.Xauthority}"
if [ ! -r "${XAUTHORITY}" ] && [ -r /home/petalinux/.Xauthority ]; then
  XAUTHORITY="/home/petalinux/.Xauthority"
fi
if [ ! -r "${XAUTHORITY}" ] && [ -r /root/.Xauthority ]; then
  XAUTHORITY="/root/.Xauthority"
fi
export XAUTHORITY

normalize_display "${DISPLAY:-:0}"
mkdir -p "$(dirname "${LOG_FILE}")" 2>/dev/null || true
touch "${LOG_FILE}" 2>/dev/null || true
chmod 666 "${LOG_FILE}" 2>/dev/null || true
if [ "$(id -u)" -eq 0 ] && command -v chown >/dev/null 2>&1; then
  chown "${TARGET_USER}:${TARGET_USER}" "$(dirname "${LOG_FILE}")" "${LOG_FILE}" 2>/dev/null || true
fi

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
    echo "Requested existing KV260 Event Camera window to present." >> "${LOG_FILE}" 2>&1
    exit 0
  fi
fi

if [ "$(id -u)" -eq 0 ] && command -v runuser >/dev/null 2>&1; then
  if [ "${FOREGROUND}" = "1" ]; then
    exec runuser -u "${TARGET_USER}" -m -- env \
      HOME="${HOME}" USER="${USER}" LOGNAME="${LOGNAME}" DISPLAY="${DISPLAY}" XAUTHORITY="${XAUTHORITY}" \
      LANG="${LANG}" LC_ALL="${LC_ALL}" PYTHONIOENCODING="${PYTHONIOENCODING}" NO_AT_BRIDGE="${NO_AT_BRIDGE}" \
      KV260_EVENT_CAMERA_APP_SOCKET="${APP_SOCKET}" KV260_EVENT_CAMERA_APP_LOCK_PATH="${APP_LOCK}" \
      KV260_EVENT_CAMERA_APP_LOG_FILE="${LOG_FILE}" \
      sh -c 'exec "$@" >> "${KV260_EVENT_CAMERA_APP_LOG_FILE}" 2>&1' sh \
      python3 "${WORKDIR}/kv260-event-camera-app.py"
  fi

  setsid -f runuser -u "${TARGET_USER}" -m -- env \
    HOME="${HOME}" USER="${USER}" LOGNAME="${LOGNAME}" DISPLAY="${DISPLAY}" XAUTHORITY="${XAUTHORITY}" \
    LANG="${LANG}" LC_ALL="${LC_ALL}" PYTHONIOENCODING="${PYTHONIOENCODING}" NO_AT_BRIDGE="${NO_AT_BRIDGE}" \
    KV260_EVENT_CAMERA_APP_SOCKET="${APP_SOCKET}" KV260_EVENT_CAMERA_APP_LOCK_PATH="${APP_LOCK}" \
    KV260_EVENT_CAMERA_APP_LOG_FILE="${LOG_FILE}" \
    sh -c 'exec "$@" >> "${KV260_EVENT_CAMERA_APP_LOG_FILE}" 2>&1' sh \
    python3 "${WORKDIR}/kv260-event-camera-app.py"
  exit 0
fi

if [ "${FOREGROUND}" = "1" ]; then
  exec python3 "${WORKDIR}/kv260-event-camera-app.py" >> "${LOG_FILE}" 2>&1
fi

setsid -f python3 "${WORKDIR}/kv260-event-camera-app.py" >> "${LOG_FILE}" 2>&1
exit 0
