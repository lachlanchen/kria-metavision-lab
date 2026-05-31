#!/usr/bin/env sh
set -eu

BOARD_IP="${KV260_BOARD_IP:-}"
SSH_USER="petalinux"
VIDEO_DEV="/dev/video0"
DISPLAY="${KV260_DISPLAY:-:0}"
ACTION="start"
KEEP_CAPTURE_SESSION=0
RECORD=1
REALTIME_MODE=0
NICE_ADJ=0
CPU_MASK=""
SUDO_PASSWORD="${KV260_SUDO_PASSWORD:-}"

usage() {
  cat <<'EOF'
Usage:
  kv260-event-visual-gui.sh [--board IP] [--user USER] [--video /dev/videoX]
                              [--display :0] [--start|--stop|--status]
                              [--keep-capture] [--low-latency]
                              [--no-record|--record] [--nice N]
                              [--cpu-mask N]

Actions:
  --start      Start (or restart) the native Metavision GUI viewer on the board.
  --stop       Stop the viewer process started by this script.
  --status     Show viewer + capture session status.

Defaults:
  --board  <kv260-ip> or KV260_BOARD_IP
  --user   petalinux
  --video  /dev/video0
  --display :0

Behavior:
  --start stops the text-only event-visual tmux session by default so it doesn't
  hold /dev/video and block the viewer. Use --keep-capture to skip that stop.
  --low-latency: run with fewer overheads, no recording, higher priority.
  --no-record:   run viewer live only (no -o file output).
  --nice N:      set process nice value.
  --cpu-mask N:  pin process to selected CPU core list.
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
    --display)
      DISPLAY="$2"
      shift 2
      ;;
    --start|--stop|--status)
      ACTION="${1#--}"
      shift
      ;;
    --keep-capture)
      KEEP_CAPTURE_SESSION=1
      shift
      ;;
    --low-latency)
      REALTIME_MODE=1
      RECORD=0
      NICE_ADJ=0
      shift
      ;;
    --no-record)
      RECORD=0
      shift
      ;;
    --record)
      RECORD=1
      shift
      ;;
    --nice)
      NICE_ADJ="$2"
      shift 2
      ;;
    --cpu-mask)
      CPU_MASK="$2"
      shift 2
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
  "${SSH_USER}@${BOARD_IP}" \
  "LC_ALL=en_GB.UTF-8 LC_CTYPE=en_GB.UTF-8 LANG=en_GB.UTF-8 \
   VIDEO_DEV='${VIDEO_DEV}' \
   DISPLAY_TARGET='${DISPLAY}' ACTION='${ACTION}' \
   KEEP_CAPTURE_SESSION='${KEEP_CAPTURE_SESSION}' \
   RECORD='${RECORD}' \
   REALTIME_MODE='${REALTIME_MODE}' \
   NICE_ADJ='${NICE_ADJ}' \
   CPU_MASK='${CPU_MASK}' \
   SUDO_PASSWORD='${SUDO_PASSWORD}' sh -s" <<'REMOTE'
set -eu

ACTION="${ACTION}"
VIDEO_DEV="${VIDEO_DEV}"
DISPLAY_TARGET="${DISPLAY_TARGET}"
KEEP_CAPTURE_SESSION="${KEEP_CAPTURE_SESSION}"
RECORD="${RECORD}"
REALTIME_MODE="${REALTIME_MODE}"
NICE_ADJ="${NICE_ADJ}"
CPU_MASK="${CPU_MASK}"
SUDO_PASSWORD="${SUDO_PASSWORD}"
TMUX="tmux -L kv260-event-visual"
SESSION="event-visual"
VIEWER_PID="/tmp/event-visual-viewer.pid"
VIEWER_LOG="/tmp/event-visual-viewer.log"
VIEWER_RAW="/tmp/event_visual_gui_demo.raw"

mkdir -p /tmp/event-visual

start_viewer() {
  # stop text capture session if it's running so it does not own /dev/video
  if [ "${KEEP_CAPTURE_SESSION}" != "1" ]; then
    if ${TMUX} has-session -t "${SESSION}" 2>/dev/null; then
      ${TMUX} kill-session -t "${SESSION}" || true
      echo "Stopped capture session: ${SESSION}"
    fi
  fi

  if [ "${DISPLAY_TARGET#*:}" = "${DISPLAY_TARGET}" ]; then
    X_DISPLAY=":${DISPLAY_TARGET}"
  else
    X_DISPLAY="${DISPLAY_TARGET}"
  fi
  SOCKET_ID="${X_DISPLAY#:}"
  SOCKET_PATH="/tmp/.X11-unix/X${SOCKET_ID}"

  # If X socket is missing, try to start a local matchbox/X stack as root.
  if [ ! -S "${SOCKET_PATH}" ]; then
    if command -v xinit >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1 && [ -n "${SUDO_PASSWORD}" ]; then
      echo "${SUDO_PASSWORD}" | sudo -S xinit /etc/X11/Xsession -- "${X_DISPLAY}" vt7 -nolisten tcp -noreset -br -pn >/tmp/event-visual-gui-xinit.log 2>&1 &
      echo "Started X with sudo (pid $!). Waiting for ${SOCKET_PATH} ..."
      i=0
      while [ ! -S "${SOCKET_PATH}" ] && [ "${i}" -lt 20 ]; do
        sleep 1
        i=$((i + 1))
      done
    else
      echo "No X socket found at ${SOCKET_PATH}."
      echo "Start X/Matchbox on the board manually first (or pass SUDO password via KV260_SUDO_PASSWORD)."
      exit 1
    fi
  fi

  if [ ! -S "${SOCKET_PATH}" ]; then
    echo "X socket still unavailable: ${SOCKET_PATH}"
    exit 1
  fi

  # avoid race if viewer already running
  if [ -f "${VIEWER_PID}" ] && pid="$(cat "${VIEWER_PID}")" && kill -0 "${pid}" 2>/dev/null; then
    echo "Viewer already running (pid=${pid})."
    exit 0
  fi

  : > /tmp/event-visual-viewer-launch.sh
  {
    echo "#!/bin/sh"
    echo "set -eu"
    echo "export DISPLAY=\"${X_DISPLAY}\""
    echo 'export XAUTHORITY="${XAUTHORITY:-${HOME}/.Xauthority}"'
    echo "export NO_AT_BRIDGE=1"
    if [ "${REALTIME_MODE}" = "1" ]; then
      echo "export GDK_BACKEND=x11"
      echo "export QT_X11_NO_MITSHM=1"
    fi
    if [ "${RECORD}" = "1" ]; then
      echo "exec /usr/bin/metavision_viewer -o \"${VIEWER_RAW}\""
    else
      echo "exec /usr/bin/metavision_viewer"
    fi
  } > /tmp/event-visual-viewer-launch.sh
  chmod +x /tmp/event-visual-viewer-launch.sh

  LAUNCH_CMD="sh /tmp/event-visual-viewer-launch.sh"
  if [ -n "${CPU_MASK}" ] && command -v taskset >/dev/null 2>&1; then
    LAUNCH_CMD="taskset -c ${CPU_MASK} ${LAUNCH_CMD}"
  elif [ -n "${CPU_MASK}" ]; then
    echo "taskset not available on target; ignoring --cpu-mask=${CPU_MASK}"
  fi
  if [ "${NICE_ADJ}" -ne 0 ] && command -v nice >/dev/null 2>&1; then
    if sh -c "nice -n ${NICE_ADJ} true" >/dev/null 2>&1; then
      LAUNCH_CMD="nice -n ${NICE_ADJ} ${LAUNCH_CMD}"
    else
      echo "nice -n ${NICE_ADJ} is not permitted for this user; running with default priority."
      NICE_ADJ=0
    fi
  fi

  nohup sh -c "${LAUNCH_CMD}" >"${VIEWER_LOG}" 2>&1 < /dev/null &
  echo $! > "${VIEWER_PID}"
  MODE_LABEL="recording to ${VIEWER_RAW}"
  [ "${RECORD}" = "0" ] && MODE_LABEL="live only (no recording)"
  echo "Started viewer (pid $!). Mode: ${MODE_LABEL}. NICE=${NICE_ADJ}, CPU_MASK=${CPU_MASK:-auto}."
}

stop_viewer() {
  if [ -f "${VIEWER_PID}" ]; then
    pid="$(cat "${VIEWER_PID}")"
    if kill "${pid}" 2>/dev/null; then
      echo "Stopped viewer (pid ${pid})."
    fi
    rm -f "${VIEWER_PID}"
  else
    if pgrep -f '/usr/bin/metavision_viewer' >/dev/null 2>&1; then
      pkill -f '/usr/bin/metavision_viewer' || true
      echo "Stopped metavision_viewer processes."
    else
      echo "No managed viewer process found."
    fi
  fi
}

status_viewer() {
  if [ -f "${VIEWER_PID}" ]; then
    pid="$(cat "${VIEWER_PID}")"
    if kill -0 "${pid}" 2>/dev/null; then
      echo "Viewer running (pid=${pid})."
    else
      echo "Viewer pid file exists but process is gone."
    fi
  else
    echo "No viewer pid file."
  fi
  if pgrep -af '/usr/bin/metavision_viewer' >/dev/null 2>&1; then
    pgrep -af '/usr/bin/metavision_viewer'
  fi

  echo "--- capture session ---"
  if ${TMUX} has-session -t "${SESSION}" 2>/dev/null; then
    echo "event-visual tmux session is running."
  else
    echo "No event-visual tmux session."
  fi

  echo "--- X state ---"
  ls -l /tmp/.X11-unix/X* 2>/dev/null || echo "No X socket present."
  echo "--- viewer log tail ---"
  tail -n 30 "${VIEWER_LOG}" 2>/dev/null || true
}

case "${ACTION}" in
  start)
    start_viewer
    ;;
  stop)
    stop_viewer
    ;;
  status)
    status_viewer
    ;;
  *)
    echo "Unknown action: ${ACTION}"
    exit 1
    ;;
esac
REMOTE
