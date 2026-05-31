#!/usr/bin/env sh
set -eu

WORKDIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_USER="${KV260_DESKTOP_USER:-petalinux}"
LOG_FILE="${KV260_PANEL_LOG:-/tmp/kv260-metavision-control-panel-${TARGET_USER}.log}"

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
export XAUTHORITY="${XAUTHORITY:-${HOME}/.Xauthority}"
if [ ! -r "${XAUTHORITY}" ] && [ -r /home/petalinux/.Xauthority ]; then
  XAUTHORITY="/home/petalinux/.Xauthority"
fi
if [ ! -r "${XAUTHORITY}" ] && [ -r /root/.Xauthority ]; then
  XAUTHORITY="/root/.Xauthority"
fi
export XAUTHORITY

normalize_display "${DISPLAY:-:0}"
touch "${LOG_FILE}" 2>/dev/null || true
chmod 666 "${LOG_FILE}" 2>/dev/null || true

if [ "$(id -u)" -eq 0 ] && command -v chown >/dev/null 2>&1; then
  chown "${TARGET_USER}:${TARGET_USER}" "${LOG_FILE}" 2>/dev/null || true
fi

if [ "$(id -u)" -eq 0 ] && command -v runuser >/dev/null 2>&1; then
  exec runuser -u "${TARGET_USER}" -m -- env \
    HOME="${HOME}" USER="${USER}" LOGNAME="${LOGNAME}" DISPLAY="${DISPLAY}" XAUTHORITY="${XAUTHORITY}" \
    python3 "${WORKDIR}/kv260-metavision-control-panel.py" >> "${LOG_FILE}" 2>&1
fi

exec python3 "${WORKDIR}/kv260-metavision-control-panel.py" >> "${LOG_FILE}" 2>&1
