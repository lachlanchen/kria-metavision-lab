#!/usr/bin/env sh
set -eu

WORKDIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${WORKDIR%/scripts}"
PROJECT_DIR="${PROJECT_DIR%/}"
TARGET_USER="${KV260_DESKTOP_USER:-petalinux}"
LOG_FILE="${KV260_MENU_LOG:-/tmp/kv260-launch-desktop-viewer-${TARGET_USER}.log}"
FORCE_START=0
REARM_CAMERA=0
RECORD=0
LOW_LATENCY=1
LOCK_DIR="${KV260_MENU_LOCK_DIR:-/tmp/kv260-metavision-launch.lock}"

usage() {
  cat <<'EOF'
Usage:
  kv260-launch-desktop-viewer.sh [--live|--record|--recover|--force] [--rearm]

Defaults:
  --live      Open the viewer once as petalinux. If already open, leave it alone.

Modes:
  --record    Open with an output .raw path enabled for event recording.
  --recover   Force restart and rearm the Prophesee camera stack.
  --force     Force restart an existing viewer.
  --rearm     Rearm camera stack before launch.
EOF
}

log_msg() {
  { printf '%s [desktop-launcher] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "${LOG_FILE}"; } 2>/dev/null || true
}

viewer_process_exists() {
  ps -e -o comm= 2>/dev/null | awk '$1 == "metavision_view" || $1 == "metavision_viewer" { found=1 } END { exit found ? 0 : 1 }'
}

acquire_launch_lock() {
  if mkdir "${LOCK_DIR}" 2>/dev/null; then
    printf '%s\n' "$$" > "${LOCK_DIR}/pid" 2>/dev/null || true
    trap 'release_launch_lock' EXIT HUP INT TERM
    return 0
  fi

  old_pid="$(cat "${LOCK_DIR}/pid" 2>/dev/null || true)"
  if [ -n "${old_pid}" ] && ps -p "${old_pid}" >/dev/null 2>&1; then
    log_msg "Another launcher instance is already running (pid=${old_pid}); ignoring duplicate click."
    exit 0
  fi

  rm -rf "${LOCK_DIR}" 2>/dev/null || true
  if mkdir "${LOCK_DIR}" 2>/dev/null; then
    printf '%s\n' "$$" > "${LOCK_DIR}/pid" 2>/dev/null || true
    trap 'release_launch_lock' EXIT HUP INT TERM
    return 0
  fi

  log_msg "Could not acquire launcher lock; ignoring duplicate click."
  exit 0
}

release_launch_lock() {
  if [ -d "${LOCK_DIR}" ]; then
    old_pid="$(cat "${LOCK_DIR}/pid" 2>/dev/null || true)"
    if [ "${old_pid}" = "$$" ]; then
      rm -rf "${LOCK_DIR}" 2>/dev/null || true
    fi
  fi
}

notify_launch_error() {
  _msg="$1"
  log_msg "${_msg}"
  if command -v xmessage >/dev/null 2>&1; then
    DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-${HOME}/.Xauthority}" xmessage -center "${_msg}" >/dev/null 2>&1 < /dev/null || true
  elif command -v kdialog >/dev/null 2>&1; then
    DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-${HOME}/.Xauthority}" kdialog --msgbox "${_msg}" >/dev/null 2>&1 < /dev/null || true
  fi
}

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

while [ "$#" -gt 0 ]; do
  case "$1" in
    --live|--start)
      RECORD=0
      LOW_LATENCY=1
      shift
      ;;
    --record)
      RECORD=1
      LOW_LATENCY=0
      shift
      ;;
    --recover)
      FORCE_START=1
      REARM_CAMERA=1
      RECORD=0
      LOW_LATENCY=1
      shift
      ;;
    --force)
      FORCE_START=1
      shift
      ;;
    --rearm)
      REARM_CAMERA=1
      shift
      ;;
    --low-latency)
      LOW_LATENCY=1
      shift
      ;;
    --no-record)
      RECORD=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

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
  X_DISPLAY=":${_display_num}"
  X_DISPLAY_SOCKET="/tmp/.X11-unix/X${_display_num}"
  if ! [ -S "${X_DISPLAY_SOCKET}" ]; then
    SOCKET_FALLBACK="$(ls /tmp/.X11-unix/X* 2>/dev/null | head -n 1 || true)"
    if [ -n "${SOCKET_FALLBACK}" ]; then
      X_DISPLAY_NUM="${SOCKET_FALLBACK##*X}"
      X_DISPLAY=":${X_DISPLAY_NUM}"
      X_DISPLAY_SOCKET="${SOCKET_FALLBACK}"
    else
      X_DISPLAY_SOCKET="/tmp/.X11-unix/X${_display_num}"
    fi
  fi
}

TARGET_HOME="$(resolve_home)"
export HOME="${TARGET_HOME}"
export USER="${TARGET_USER}"
export LOGNAME="${TARGET_USER}"
export XAUTHORITY="${XAUTHORITY:-${HOME}/.Xauthority}"
if [ ! -r "${XAUTHORITY}" ] && [ -r "${HOME}/.Xauthority" ]; then
  XAUTHORITY="${HOME}/.Xauthority"
fi
if [ ! -r "${XAUTHORITY}" ] && [ -r /home/petalinux/.Xauthority ]; then
  XAUTHORITY="/home/petalinux/.Xauthority"
fi
if [ ! -r "${XAUTHORITY}" ] && [ -r /root/.Xauthority ]; then
  XAUTHORITY="/root/.Xauthority"
fi
export XAUTHORITY

HELPER_LOG="${HOME}/.cache/kv260-event-viewer/metavision-viewer-wrapper.log"
mkdir -p "$(dirname "${HELPER_LOG}")" 2>/dev/null || true
touch "${HELPER_LOG}" 2>/dev/null || true
chmod 666 "${HELPER_LOG}" 2>/dev/null || true
if [ "$(id -u)" -eq 0 ] && command -v chown >/dev/null 2>&1; then
  chown "${TARGET_USER}:${TARGET_USER}" "$(dirname "${HELPER_LOG}")" "${HELPER_LOG}" 2>/dev/null || true
fi
touch "${LOG_FILE}" 2>/dev/null || true
chmod 666 "${LOG_FILE}" 2>/dev/null || true

normalize_display "${DISPLAY-}"
DISPLAY="${X_DISPLAY}"
export DISPLAY

if ! [ -S "${X_DISPLAY_SOCKET}" ]; then
  notify_launch_error "Metavision menu launcher: no X socket for display ${DISPLAY}. Start Matchbox/X first."
  exit 1
fi

acquire_launch_lock

cd "${PROJECT_DIR}"
LAUNCH_ARGS="--start --display ${DISPLAY}"
if [ "${FORCE_START}" = "1" ]; then
  LAUNCH_ARGS="${LAUNCH_ARGS} --force"
else
  LAUNCH_ARGS="${LAUNCH_ARGS} --no-force"
fi
if [ "${REARM_CAMERA}" = "1" ]; then
  LAUNCH_ARGS="${LAUNCH_ARGS} --rearm"
else
  LAUNCH_ARGS="${LAUNCH_ARGS} --no-rearm"
fi
if [ "${RECORD}" = "1" ]; then
  LAUNCH_ARGS="${LAUNCH_ARGS} --record"
else
  LAUNCH_ARGS="${LAUNCH_ARGS} --no-record"
fi
if [ "${LOW_LATENCY}" = "1" ]; then
  LAUNCH_ARGS="${LAUNCH_ARGS} --low-latency"
fi
LAUNCHER_CMD="${WORKDIR}/kv260-event-visual-gui-local.sh ${LAUNCH_ARGS}"
:
log_msg "Launch requested as user=$(id -un) target_user=${TARGET_USER} display=${DISPLAY} force=${FORCE_START} rearm=${REARM_CAMERA} record=${RECORD} cmd=${LAUNCHER_CMD}"

has_pse_node() {
  for node in /dev/video*; do
    [ -e "${node}" ] || continue
    if v4l2-ctl -d "${node}" --all 2>/dev/null | grep -qi "Pixel Format.*'PSE"; then
      return 0
    fi
  done
  return 1
}

root_preflight_load_stack() {
  if [ "$(id -u)" -ne 0 ]; then
    return 0
  fi
  if [ "${FORCE_START}" != "1" ] && viewer_process_exists; then
    log_msg "Root preflight: viewer already running; skipping camera stack load."
    return 0
  fi
  if has_pse_node; then
    log_msg "Root preflight: PSE video node already present."
    return 0
  fi

  log_msg "Root preflight: no PSE video node; attempting Prophesee stack load."
  for loader in \
    /usr/bin/load-prophesee-kv260-imx636.sh \
    /usr/local/bin/load-prophesee-kv260-imx636.sh \
    /usr/local/sbin/load-prophesee-kv260-imx636.sh \
    /usr/bin/load-prophesee-kv260-genx320.sh \
    /usr/local/bin/load-prophesee-kv260-genx320.sh \
    /usr/local/sbin/load-prophesee-kv260-genx320.sh; do
    if [ -x "${loader}" ]; then
      log_msg "Root preflight: running ${loader}"
      "${loader}" >> "${HELPER_LOG}" 2>&1 || true
      sleep 2
      if has_pse_node; then
        log_msg "Root preflight: PSE video node present after ${loader}"
        return 0
      fi
    fi
  done

  log_msg "Root preflight: no PSE video node after loader attempts."
  return 0
}

root_preflight_load_stack

if [ "$(id -u)" -eq 0 ]; then
  if command -v runuser >/dev/null 2>&1; then
    log_msg "Using runuser"
    runuser -u "${TARGET_USER}" -m -- sh -c "${LAUNCHER_CMD} >> '${HELPER_LOG}' 2>&1"
    exit $?
  elif command -v su >/dev/null 2>&1; then
    log_msg "Using su fallback"
    su -s /bin/sh - "${TARGET_USER}" -c "${LAUNCHER_CMD} >> '${HELPER_LOG}' 2>&1"
    exit $?
  fi
  log_msg "Root switch command unavailable; falling back to local shell"
fi

log_msg "Running as non-root user."
"${WORKDIR}/kv260-event-visual-gui-local.sh" ${LAUNCH_ARGS} >> "${HELPER_LOG}" 2>&1
exit $?
