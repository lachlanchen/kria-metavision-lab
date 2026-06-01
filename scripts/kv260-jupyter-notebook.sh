#!/usr/bin/env sh
set -eu

PID_FILE="/tmp/kv260-jupyter-notebook.pid"
LOG_DIR="${HOME:-/home/petalinux}/.cache/kv260-event-camera"
LOG_FILE="${LOG_DIR}/jupyter-notebook.log"
NOTEBOOK_DIR="${KV260_JUPYTER_NOTEBOOK_DIR:-/home/petalinux/Projects}"
HOST="${KV260_JUPYTER_HOST:-127.0.0.1}"
PORT="${KV260_JUPYTER_PORT:-8888}"

usage() {
  cat <<'EOF'
Usage:
  kv260-jupyter-notebook.sh --start
  kv260-jupyter-notebook.sh --stop
  kv260-jupyter-notebook.sh --status

Starts Jupyter Notebook on 127.0.0.1:8888 for use through an SSH tunnel.
EOF
}

read_pid() {
  if [ -f "${PID_FILE}" ]; then
    awk 'NR == 1 && $1 ~ /^[0-9]+$/ { print $1; exit }' "${PID_FILE}" 2>/dev/null || true
  fi
}

pid_alive() {
  pid="$1"
  [ -n "${pid}" ] && kill -0 "${pid}" >/dev/null 2>&1
}

status() {
  pid="$(read_pid)"
  if pid_alive "${pid}"; then
    echo "jupyter: running pid=${pid} url=http://127.0.0.1:${PORT}/tree"
    return 0
  fi
  if command -v jupyter-notebook >/dev/null 2>&1; then
    running="$(jupyter-notebook list 2>/dev/null | awk -v port=":${PORT}/" '$0 ~ port { print; exit }' || true)"
    if [ -n "${running}" ]; then
      echo "jupyter: running ${running}"
      return 0
    fi
  fi
  echo "jupyter: stopped"
}

start() {
  if ! command -v jupyter-notebook >/dev/null 2>&1; then
    echo "jupyter-notebook command not found" >&2
    return 2
  fi
  pid="$(read_pid)"
  if pid_alive "${pid}"; then
    status
    return 0
  fi
  mkdir -p "${LOG_DIR}" "${NOTEBOOK_DIR}"
  nohup jupyter-notebook \
    --no-browser \
    --ip="${HOST}" \
    --port="${PORT}" \
    --notebook-dir="${NOTEBOOK_DIR}" \
    --NotebookApp.token='' \
    --NotebookApp.password='' \
    --NotebookApp.open_browser=False \
    > "${LOG_FILE}" 2>&1 &
  echo "$!" > "${PID_FILE}"
  sleep 2
  status
}

stop() {
  pid="$(read_pid)"
  if pid_alive "${pid}"; then
    kill "${pid}" >/dev/null 2>&1 || true
    loops=20
    while [ "${loops}" -gt 0 ]; do
      pid_alive "${pid}" || break
      sleep 0.2
      loops=$((loops - 1))
    done
    if pid_alive "${pid}"; then
      kill -9 "${pid}" >/dev/null 2>&1 || true
    fi
  fi
  rm -f "${PID_FILE}" 2>/dev/null || true
  status
}

case "${1:-}" in
  --start)
    start
    ;;
  --stop)
    stop
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
