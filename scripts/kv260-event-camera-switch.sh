#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BOARD_SOCKET="/tmp/kv260-event-camera-app.sock"
BOARD_LOCK="/tmp/kv260-event-camera-app.lock"
X11_SOCKET="/tmp/kv260-event-camera-app-x11.sock"
X11_LOCK="/tmp/kv260-event-camera-app-x11.lock"

usage() {
  cat <<'EOF'
Usage:
  kv260-event-camera-switch.sh --board
  kv260-event-camera-switch.sh --x11
  kv260-event-camera-switch.sh --stop-board
  kv260-event-camera-switch.sh --stop-x11
  kv260-event-camera-switch.sh --stop-all
  kv260-event-camera-switch.sh --status

Only one viewer can own /dev/video0. Starting one display mode stops the other.
EOF
}

read_lock_pid() {
  lock_path="$1"
  if [ -f "${lock_path}" ]; then
    awk 'NR == 1 && $1 ~ /^[0-9]+$/ { print $1; exit }' "${lock_path}" 2>/dev/null || true
  fi
}

pid_alive() {
  pid="$1"
  [ -n "${pid}" ] && kill -0 "${pid}" >/dev/null 2>&1
}

send_socket_command() {
  socket_path="$1"
  command="$2"
  [ -S "${socket_path}" ] || return 1
  python3 - "${socket_path}" "${command}" <<'PY'
import socket
import sys

socket_path = sys.argv[1]
command = sys.argv[2].encode("utf-8")
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
    client.settimeout(0.8)
    client.connect(socket_path)
    client.sendall(command)
PY
}

wait_for_exit() {
  pid="$1"
  loops="${2:-25}"
  while [ "${loops}" -gt 0 ]; do
    if ! pid_alive "${pid}"; then
      return 0
    fi
    sleep 0.2
    loops=$((loops - 1))
  done
  return 1
}

stop_instance() {
  name="$1"
  socket_path="$2"
  lock_path="$3"
  pid="$(read_lock_pid "${lock_path}")"

  if [ -S "${socket_path}" ]; then
    send_socket_command "${socket_path}" quit >/dev/null 2>&1 || true
  fi

  if pid_alive "${pid}"; then
    wait_for_exit "${pid}" 25 || true
  fi

  if pid_alive "${pid}"; then
    echo "${name}: process ${pid} did not exit after quit, sending TERM"
    kill "${pid}" >/dev/null 2>&1 || true
    wait_for_exit "${pid}" 15 || true
  fi

  if pid_alive "${pid}"; then
    echo "${name}: process ${pid} did not exit after TERM, sending KILL"
    kill -9 "${pid}" >/dev/null 2>&1 || true
    wait_for_exit "${pid}" 10 || true
  fi

  if ! pid_alive "${pid}"; then
    rm -f "${socket_path}" "${lock_path}" 2>/dev/null || true
  fi
}

stop_native_viewer() {
  if [ -x "${SCRIPT_DIR}/kv260-event-visual-gui-local.sh" ]; then
    "${SCRIPT_DIR}/kv260-event-visual-gui-local.sh" --stop --force >/dev/null 2>&1 || true
  fi
}

video0_owners() {
  if command -v fuser >/dev/null 2>&1; then
    fuser /dev/video0 2>/dev/null || true
  fi
}

wait_video0_free() {
  loops="${1:-25}"
  while [ "${loops}" -gt 0 ]; do
    owners="$(video0_owners)"
    if [ -z "${owners}" ]; then
      return 0
    fi
    sleep 0.2
    loops=$((loops - 1))
  done
  return 1
}

force_release_video0() {
  wait_video0_free 25 && return 0
  owners="$(video0_owners)"
  if [ -z "${owners}" ]; then
    return 0
  fi
  echo "/dev/video0 still owned by:${owners}; sending TERM"
  for pid in ${owners}; do
    kill "${pid}" >/dev/null 2>&1 || true
  done
  wait_video0_free 15 && return 0
  owners="$(video0_owners)"
  if [ -n "${owners}" ]; then
    echo "/dev/video0 still owned by:${owners}; sending KILL"
    for pid in ${owners}; do
      kill -9 "${pid}" >/dev/null 2>&1 || true
    done
    wait_video0_free 10 || true
  fi
}

start_board() {
  stop_instance "windows-x11" "${X11_SOCKET}" "${X11_LOCK}"
  stop_native_viewer
  force_release_video0
  DISPLAY=:0 XAUTHORITY=/home/petalinux/.Xauthority "${SCRIPT_DIR}/kv260-event-camera-app.sh"
}

start_x11() {
  if [ -z "${DISPLAY:-}" ]; then
    echo "DISPLAY is not set. Use SSH X forwarding for Windows X11 mode." >&2
    exit 2
  fi
  stop_instance "board-desktop" "${BOARD_SOCKET}" "${BOARD_LOCK}"
  stop_native_viewer
  force_release_video0
  "${SCRIPT_DIR}/kv260-event-camera-x11.sh"
}

print_instance_status() {
  name="$1"
  socket_path="$2"
  lock_path="$3"
  pid="$(read_lock_pid "${lock_path}")"
  if pid_alive "${pid}"; then
    echo "${name}: running pid=${pid} socket=${socket_path}"
  else
    echo "${name}: stopped"
  fi
}

status() {
  print_instance_status "board-desktop" "${BOARD_SOCKET}" "${BOARD_LOCK}"
  print_instance_status "windows-x11" "${X11_SOCKET}" "${X11_LOCK}"
  if command -v fuser >/dev/null 2>&1; then
    owners="$(fuser /dev/video0 2>/dev/null || true)"
    if [ -n "${owners}" ]; then
      echo "/dev/video0 owners:${owners}"
    else
      echo "/dev/video0 owners: none"
    fi
  fi
}

case "${1:-}" in
  --board)
    start_board
    ;;
  --x11)
    start_x11
    ;;
  --stop-board)
    stop_instance "board-desktop" "${BOARD_SOCKET}" "${BOARD_LOCK}"
    ;;
  --stop-x11)
    stop_instance "windows-x11" "${X11_SOCKET}" "${X11_LOCK}"
    ;;
  --stop-all)
    stop_instance "windows-x11" "${X11_SOCKET}" "${X11_LOCK}"
    stop_instance "board-desktop" "${BOARD_SOCKET}" "${BOARD_LOCK}"
    stop_native_viewer
    ;;
  --status)
    status
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
