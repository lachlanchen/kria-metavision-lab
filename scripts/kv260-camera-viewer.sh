#!/usr/bin/env sh
set -eu

WORKDIR="$(cd "$(dirname "$0")" && pwd)"
DISPLAY_TARGET="${KV260_DISPLAY:-:0}"
ACTION="start"
VIDEO_DEV=""
CAMERA_TYPE="auto"
KEEP_CAPTURE_SESSION=0
EVENT_RECORD=0
LOW_LATENCY=0
NICE_ADJ=0
CPU_MASK=""
FRAME_FPS=0
FRAME_WIDTH=""
FRAME_HEIGHT=""
PID_DIR="/tmp/kv260-camera-viewer"
EVENT_PID_FILE="/tmp/event-visual-viewer.pid"
FRAME_PID_FILE="${PID_DIR}/kv260-frame-viewer.pid"
FRAME_LOG="${PID_DIR}/kv260-frame-viewer.log"
mkdir -p "${PID_DIR}"

event_viewer() {
  set -- "${WORKDIR}/kv260-event-visual-gui-local.sh" --display "${DISPLAY_TARGET}" --start --force --rearm
  [ "${KEEP_CAPTURE_SESSION}" = "1" ] && set -- "$@" --keep-capture
  [ "${EVENT_RECORD}" = "1" ] && set -- "$@" --record || set -- "$@" --no-record
  [ "${LOW_LATENCY}" = "1" ] && set -- "$@" --low-latency
  [ -n "${NICE_ADJ}" ] && [ "${NICE_ADJ}" != "0" ] && set -- "$@" --nice "${NICE_ADJ}"
  [ -n "${CPU_MASK}" ] && set -- "$@" --cpu-mask "${CPU_MASK}"
  "$@"
}

usage() {
  cat <<'EOF'
Usage:
  kv260-camera-viewer.sh [--start|--stop|--status|--list]
                         [--video /dev/videoN] [--type auto|event|frame]
                         [--display :0] [--low-latency] [--no-record|--record]
                         [--nice N] [--cpu-mask N]
                         [--frame-fps N] [--frame-width W --frame-height H]
                         [--keep-capture]

Examples:
  ./kv260-camera-viewer.sh --start
  ./kv260-camera-viewer.sh --start --type frame --video /dev/video0
  ./kv260-camera-viewer.sh --start --type event --low-latency --video /dev/video0
  ./kv260-camera-viewer.sh --list
  ./kv260-camera-viewer.sh --stop
EOF
}

is_event_camera() {
  dev="$1"
  fmt="$(v4l2-ctl -d "$dev" --all 2>/dev/null | awk -F"'" '/Pixel Format[[:space:]]*:/ {print $2; exit}')"
  case "$fmt" in
    *PSE*|*pse*|*PSEE*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

validate_type() {
  case "$1" in
    auto|event|frame) ;;
    *)
      echo "Invalid --type '$1' (expected auto|event|frame)."
      exit 1
      ;;
  esac
}

list_cameras() {
  found=0
  echo "Detected /dev/video* devices:"
  for dev in /dev/video*; do
    [ -e "$dev" ] || continue
    fmt="$(v4l2-ctl -d "$dev" --all 2>/dev/null | awk -F"'" '/Pixel Format[[:space:]]*:/ {print $2; exit}')"
    if [ -z "$fmt" ]; then
      ctype="unknown"
    else
      if is_event_camera "$dev"; then
        ctype="event"
      else
        ctype="frame"
      fi
    fi
    found=1
    printf '  %s  format=%s  type=%s\n' "$dev" "${fmt:-?}" "$ctype"
  done
  [ "$found" -eq 0 ] && echo "  (none)"
  return 0
}

resolve_device_and_type() {
  if [ -n "${VIDEO_DEV}" ]; then
    if [ ! -e "${VIDEO_DEV}" ]; then
      echo "ERROR: device ${VIDEO_DEV} does not exist."
      exit 1
    fi
    DEV="${VIDEO_DEV}"
    if [ "${CAMERA_TYPE}" = "auto" ]; then
      if is_event_camera "${DEV}"; then
        KIND="event"
      else
        KIND="frame"
      fi
    else
      if [ "${CAMERA_TYPE}" = "event" ] && ! is_event_camera "${DEV}"; then
        echo "ERROR: ${VIDEO_DEV} is not an event camera. Choose --type frame or auto."
        exit 1
      fi
      if [ "${CAMERA_TYPE}" = "frame" ] && is_event_camera "${DEV}"; then
        echo "ERROR: ${VIDEO_DEV} is an event camera (PSE format), not a frame/V4L2 camera."
        exit 1
      fi
      KIND="${CAMERA_TYPE}"
    fi
    return 0
  fi

  for dev in /dev/video*; do
    [ -e "$dev" ] || continue
    if [ "${CAMERA_TYPE}" = "event" ] && is_event_camera "$dev"; then
      DEV="$dev"; KIND="event"; return 0
    fi
    if [ "${CAMERA_TYPE}" = "frame" ] && ! is_event_camera "$dev"; then
      DEV="$dev"; KIND="frame"; return 0
    fi
  done

  if [ "${CAMERA_TYPE}" = "event" ] || [ "${CAMERA_TYPE}" = "frame" ]; then
    if [ "${CAMERA_TYPE}" = "frame" ]; then
      echo "No non-PSE/frame camera found under /dev/video*. Connect a frame/V4L2 camera first."
    else
      echo "No PSE event camera found under /dev/video*. Ensure the Prophesee load script is running."
    fi
    exit 1
  fi

  # auto fallback: prefer first available
  for dev in /dev/video*; do
    [ -e "$dev" ] || continue
    DEV="$dev"
    if is_event_camera "$dev"; then
      KIND="event"
    else
      KIND="frame"
    fi
    return 0
  done

  echo "No /dev/video device found."
  exit 1
}

check_display_socket() {
  if [ "${DISPLAY_TARGET#*:}" = "${DISPLAY_TARGET}" ]; then
    X_DISPLAY=":${DISPLAY_TARGET}"
  else
    X_DISPLAY="${DISPLAY_TARGET}"
  fi
  SOCKET_PATH="/tmp/.X11-unix/X${X_DISPLAY#:}"
  if [ ! -S "${SOCKET_PATH}" ]; then
    echo "No X socket at ${SOCKET_PATH}. Start Matchbox/X on ${X_DISPLAY} first."
    exit 1
  fi
  export DISPLAY="${X_DISPLAY}"
  export XAUTHORITY="${XAUTHORITY:-${HOME}/.Xauthority}"
}

start_event() {
  check_display_socket
  event_viewer
}

start_frame() {
  check_display_socket
  if [ -f "$FRAME_PID_FILE" ] && kill -0 "$(cat "$FRAME_PID_FILE")" 2>/dev/null; then
    echo "Frame viewer already running (pid $(cat "$FRAME_PID_FILE"))."
    exit 0
  fi
  if [ -f "$EVENT_PID_FILE" ]; then
    echo "Stopping event viewer before launching frame viewer (pid $(cat "$EVENT_PID_FILE"))."
    "${WORKDIR}/kv260-event-visual-gui-local.sh" --stop --force >/dev/null 2>&1 || true
  fi
  rm -f "$FRAME_LOG"
  set -- \
    "$WORKDIR/kv260-frame-camera-viewer.py" \
    --device "$DEV" \
    --title "KV260 Frame Viewer ${DEV}"
  if [ "${FRAME_FPS}" != "0" ]; then
    set -- "$@" --fps "${FRAME_FPS}"
  fi
  if [ -n "${FRAME_WIDTH}" ]; then
    set -- "$@" --width "${FRAME_WIDTH}"
  fi
  if [ -n "${FRAME_HEIGHT}" ]; then
    set -- "$@" --height "${FRAME_HEIGHT}"
  fi
  nohup "$@" >"${FRAME_LOG}" 2>&1 &
  echo "$!" > "$FRAME_PID_FILE"
  echo "Started frame viewer (pid $!)."
}

stop_viewer() {
  stop_file="$FRAME_PID_FILE"
  if [ -f "$stop_file" ]; then
    pid="$(cat "$stop_file")"
    if kill "$pid" 2>/dev/null; then
      echo "Stopped frame viewer pid $pid."
    fi
    rm -f "$stop_file"
  else
    if pgrep -f "/kv260-frame-camera-viewer.py" >/dev/null 2>&1; then
      pkill -f "/kv260-frame-camera-viewer.py" || true
      echo "Stopped frame viewer process(es) by name."
    else
      echo "No frame viewer pid file."
    fi
  fi
  # Also stop event viewer to avoid camera ownership conflicts.
  "${WORKDIR}/kv260-event-visual-gui-local.sh" --stop --force || true
  [ -f "$EVENT_PID_FILE" ] && rm -f "$EVENT_PID_FILE"
}

status_viewer() {
  echo "Camera nodes:"
  list_cameras
  if [ -f "$EVENT_PID_FILE" ]; then
    pid="$(cat "$EVENT_PID_FILE")"
    if kill -0 "$pid" 2>/dev/null; then
      echo "Event viewer running: pid=$pid"
    else
      echo "Event pid file exists but process is not active."
    fi
  fi
  if [ -f "$FRAME_PID_FILE" ]; then
    pid="$(cat "$FRAME_PID_FILE")"
    if kill -0 "$pid" 2>/dev/null; then
      echo "Frame viewer running: pid=$pid"
    else
      echo "Frame viewer pid file exists but process is not active."
    fi
  fi
  if pgrep -f "/kv260-frame-camera-viewer.py" >/dev/null 2>&1; then
    echo "Frame viewer processes:"
    pgrep -af "/kv260-frame-camera-viewer.py"
  fi
  if pgrep -f "/usr/bin/metavision_viewer" >/dev/null 2>&1; then
    echo "Event viewer processes:"
    pgrep -af "/usr/bin/metavision_viewer"
  fi
  if ! pgrep -f "/usr/bin/metavision_viewer" >/dev/null 2>&1 && \
     ! pgrep -f "/kv260-frame-camera-viewer.py" >/dev/null 2>&1; then
    echo "No active viewer process found."
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --video)
      [ $# -lt 2 ] && { echo "Missing value for --video"; usage; exit 1; }
      VIDEO_DEV="$2"; shift 2;;
    --type)
      [ $# -lt 2 ] && { echo "Missing value for --type"; usage; exit 1; }
      CAMERA_TYPE="$2"; validate_type "$CAMERA_TYPE"; shift 2;;
    --display)
      [ $# -lt 2 ] && { echo "Missing value for --display"; usage; exit 1; }
      DISPLAY_TARGET="$2"; shift 2;;
    --start|--stop|--status|--list)
      ACTION="${1#--}"
      shift;;
    --record)
      EVENT_RECORD=1; shift;;
    --no-record)
      EVENT_RECORD=0; shift;;
    --low-latency)
      LOW_LATENCY=1; FRAME_FPS=0; shift;;
    --nice)
      [ $# -lt 2 ] && { echo "Missing value for --nice"; usage; exit 1; }
      NICE_ADJ="$2"; shift 2;;
    --cpu-mask)
      [ $# -lt 2 ] && { echo "Missing value for --cpu-mask"; usage; exit 1; }
      CPU_MASK="$2"; shift 2;;
    --frame-fps)
      [ $# -lt 2 ] && { echo "Missing value for --frame-fps"; usage; exit 1; }
      FRAME_FPS="$2"; shift 2;;
    --frame-width)
      [ $# -lt 2 ] && { echo "Missing value for --frame-width"; usage; exit 1; }
      FRAME_WIDTH="$2"; shift 2;;
    --frame-height)
      [ $# -lt 2 ] && { echo "Missing value for --frame-height"; usage; exit 1; }
      FRAME_HEIGHT="$2"; shift 2;;
    --keep-capture)
      KEEP_CAPTURE_SESSION="1"; shift;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown argument: $1"; usage; exit 1;;
  esac
done

case "$ACTION" in
  list)
    list_cameras
    exit 0
    ;;
  status)
    status_viewer
    exit 0
    ;;
  stop)
    stop_viewer
    exit 0
    ;;
  start)
    resolve_device_and_type
    echo "Using ${DEV} as ${KIND} camera."
    if [ "$KIND" = "event" ]; then
      start_event
    elif [ "$KIND" = "frame" ]; then
      start_frame
    else
      echo "Could not classify ${DEV}. Use --type event or --type frame explicitly."
      exit 1
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac
