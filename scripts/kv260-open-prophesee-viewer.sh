#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_USER="${KV260_DESKTOP_USER:-petalinux}"

normalize_display() {
  _raw="${1:-:0}"
  if printf '%s' "${_raw}" | grep -q ":"; then
    _display_num="${_raw##*:}"
  else
    _display_num="${_raw#:}"
  fi
  _display_num="${_display_num%.0}"
  case "${_display_num}" in
    ''|*[!0-9]*)
      _display_num=0
      ;;
  esac
  _display=":${_display_num}"
  export DISPLAY="${_display}"
}
resolve_user_home() {
  user="$1"
  home_guess=""
  if command -v getent >/dev/null 2>&1; then
    home_guess="$(getent passwd "${user}" | awk -F: '{print $6}' 2>/dev/null || true)"
  else
    home_guess="$(awk -F: -v user="${user}" '$1==user {print $6; exit}' /etc/passwd 2>/dev/null || true)"
  fi
  if [ -z "${home_guess}" ] || [ ! -d "${home_guess}" ]; then
    home_guess="/home/${user}"
  fi
  printf '%s\n' "${home_guess}"
}

pick_xauthority() {
  candidate="${XAUTHORITY-}"
  if [ -z "${candidate}" ] || [ ! -r "${candidate}" ]; then
    candidate="${HOME}/.Xauthority"
  fi
  if [ ! -r "${candidate}" ] && [ -r /home/petalinux/.Xauthority ]; then
    candidate="/home/petalinux/.Xauthority"
  fi
  if [ ! -r "${candidate}" ] && [ -r /root/.Xauthority ]; then
    candidate="/root/.Xauthority"
  fi
  printf '%s\n' "${candidate}"
}

DEFAULT_HOME="$(resolve_user_home "${TARGET_USER}")"

if [ -z "${HOME}" ] || [ ! -d "${HOME}" ]; then
  HOME="${DEFAULT_HOME}"
fi
export HOME
normalize_display "${DISPLAY:-:0}"
export USER="${TARGET_USER}"
export LOGNAME="${TARGET_USER}"

XAUTHORITY="$(pick_xauthority)"
export XAUTHORITY

PROJECT_DIR="${HOME}/Projects/kria-kv260-starter"
if [ -f "${SCRIPT_DIR}/kv260-event-visual-gui-local.sh" ]; then
  PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi
VIEWER_CMD="${PROJECT_DIR}/scripts/kv260-event-visual-gui-local.sh"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-${HOME}/.cache/kv260-event-viewer}"
if [ -z "${RUNTIME_DIR}" ] || [ "${RUNTIME_DIR}" = "/tmp" ] || [ "${RUNTIME_DIR}" = "/tmp/" ]; then
  RUNTIME_DIR="${HOME}/.cache/kv260-event-viewer"
fi
mkdir -p "${RUNTIME_DIR}"
chmod 700 "${RUNTIME_DIR}" 2>/dev/null || true
VIEWER_PID="${RUNTIME_DIR}/event-visual-viewer.pid"
LAUNCH_LOG="${RUNTIME_DIR}/metavision-viewer-launch.log"
WRAPPER_LOG="${RUNTIME_DIR}/metavision-viewer-wrapper.log"
VIEWER_LOG="${RUNTIME_DIR}/event-visual-viewer.log"

FORCE=0
AUTO_FORCE=0
SUDO_PASSWORD="${KV260_SUDO_PASSWORD:-${SUDO_PASSWORD:-}}"
while [ $# -gt 0 ]; do
  case "$1" in
    --force)
      FORCE=1
      shift
      ;;
    --no-force)
      FORCE=0
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

if [ "${FORCE}" -eq 1 ]; then
  set -- --force "$@"
fi

export DISPLAY="${DISPLAY:-:0}"

: >"${LAUNCH_LOG}"
{
  echo "[$(date)] launcher invoked: cmd='$0' args='$*' force=${FORCE}"
  echo "  USER=$(id -un 2>/dev/null || true) UID=$(id -u 2>/dev/null || true)"
  echo "  DISPLAY=${DISPLAY} HOME=${HOME} XAUTHORITY=${XAUTHORITY} RUNTIME_DIR=${RUNTIME_DIR}"
} >>"${LAUNCH_LOG}"

if [ "${FORCE}" = "1" ]; then
  if [ -f "${VIEWER_PID}" ]; then
    OLD_PID="$(cat "${VIEWER_PID}" 2>/dev/null || true)"
    if [ -n "${OLD_PID}" ] && kill -0 "${OLD_PID}" 2>/dev/null; then
      echo "Killing stale pidfile process: ${OLD_PID}" >> "${LAUNCH_LOG}"
      kill "${OLD_PID}" || true
    fi
    rm -f "${VIEWER_PID}"
  fi
  if pgrep -f '/usr/bin/metavision_viewer' >/dev/null 2>&1; then
    echo "Cleaning existing metavision_viewer processes" >> "${LAUNCH_LOG}"
    pkill -f '/usr/bin/metavision_viewer' || true
    if [ -n "${SUDO_PASSWORD}" ] && command -v sudo >/dev/null 2>&1; then
      printf '%s\n' "${SUDO_PASSWORD}" | sudo -S pkill -f '/usr/bin/metavision_viewer' >/dev/null 2>&1 || true
    fi
  fi
  if pgrep -f '/tmp/event-visual-viewer-launch.sh' >/dev/null 2>&1; then
    echo "Cleaning stale wrapper launcher process" >> "${LAUNCH_LOG}"
    pkill -f '/tmp/event-visual-viewer-launch.sh' || true
  fi
  for stale_log in "${RUNTIME_DIR}"/event-visual-viewer-launch.sh /tmp/event-visual-viewer-launch.sh; do
    [ -f "${stale_log}" ] && rm -f "${stale_log}"
  done
fi

if [ ! -x "${VIEWER_CMD}" ]; then
  {
    echo "ERROR: viewer helper missing or not executable: ${VIEWER_CMD}"
  } >> "${LAUNCH_LOG}"
  exit 1
fi

if [ "$#" -eq 0 ]; then
  set -- --start --low-latency --no-record --no-rearm --no-force
  [ "${AUTO_FORCE}" = "1" ] && set -- --force "$@"
fi

if [ "${DISPLAY}" = ":0" ] || [ "${DISPLAY}" = "0" ]; then
  set -- "$@" --display "${DISPLAY}"
elif echo "${DISPLAY}" | grep -q ":"; then
  set -- "$@" --display "${DISPLAY}"
fi

if "${VIEWER_CMD}" "$@" >>"${WRAPPER_LOG}" 2>&1; then
  # wait a moment so we can surface immediate startup failures
  i=0
  while [ "${i}" -lt 3 ] && ! pgrep -af '/usr/bin/metavision_viewer' >/dev/null 2>&1; do
    sleep 1
    i=$((i + 1))
  done

  if ! pgrep -af '/usr/bin/metavision_viewer' >/dev/null 2>&1; then
    {
      echo "Launcher completed and did not detect a running viewer yet."
      echo "Last launch/helper output:"
      tail -n 80 "${VIEWER_LOG}" 2>/dev/null || true
      if [ -f "${WRAPPER_LOG}" ]; then
        echo "--- local helper ---"
        tail -n 80 "${WRAPPER_LOG}" 2>/dev/null || true
      fi
      echo " --- End ---"
    } >> "${LAUNCH_LOG}"
  else
    echo "Viewer process confirmed by process lookup." >> "${LAUNCH_LOG}"
  fi
else
  EXIT_CODE=$?
  echo "viewer command failed with code: ${EXIT_CODE}" >> "${LAUNCH_LOG}"
  echo "launcher failed, see ${LAUNCH_LOG} (and ${VIEWER_LOG})" >> "${LAUNCH_LOG}"
fi

# Always return success so desktop launchers do not hard-fail with
# a misleading busy cursor; useful state remains in the log files.
exit 0
