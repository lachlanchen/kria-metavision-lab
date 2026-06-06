#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PID_FILE="${KV260_EVENT_API_PID_FILE:-/tmp/kv260-event-camera-api.pid}"
LOG_FILE="${KV260_EVENT_API_LOG_FILE:-${HOME:-/home/petalinux}/.cache/kv260-event-camera/api.log}"
HOST="${KV260_EVENT_API_HOST:-0.0.0.0}"
PORT="${KV260_EVENT_API_PORT:-8765}"
RECORD_DIR="${KV260_EVENT_API_RECORD_DIR:-${HOME:-/home/petalinux}/event_recordings}"
DEVICE="${KV260_EVENT_API_DEVICE:-/dev/video0}"

usage() {
  cat <<'EOF'
Usage:
  kv260-event-camera-api.sh run
  kv260-event-camera-api.sh start
  kv260-event-camera-api.sh stop
  kv260-event-camera-api.sh restart
  kv260-event-camera-api.sh status
  kv260-event-camera-api.sh tail

Environment:
  KV260_EVENT_API_HOST       default 0.0.0.0
  KV260_EVENT_API_PORT       default 8765
  KV260_EVENT_API_RECORD_DIR default ~/event_recordings
  KV260_EVENT_API_DEVICE     default /dev/video0
  KV260_EVENT_API_TOKEN      optional Bearer/X-KV260-Token auth token
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

run_api() {
  cd "${PROJECT_DIR}"
  exec python3 "${SCRIPT_DIR}/kv260-event-camera-api.py" \
    --host "${HOST}" \
    --port "${PORT}" \
    --record-dir "${RECORD_DIR}" \
    --device "${DEVICE}"
}

start_api() {
  pid="$(read_pid)"
  if pid_alive "${pid}"; then
    echo "KV260 Event Camera API already running pid=${pid}"
    return 0
  fi

  mkdir -p "$(dirname "${LOG_FILE}")" "$(dirname "${PID_FILE}")" 2>/dev/null || true
  : > "${LOG_FILE}"
  (
    cd "${PROJECT_DIR}"
    nohup python3 "${SCRIPT_DIR}/kv260-event-camera-api.py" \
      --host "${HOST}" \
      --port "${PORT}" \
      --record-dir "${RECORD_DIR}" \
      --device "${DEVICE}" >> "${LOG_FILE}" 2>&1 &
    echo "$!" > "${PID_FILE}"
  )
  sleep 1
  pid="$(read_pid)"
  if ! pid_alive "${pid}"; then
    echo "KV260 Event Camera API failed to start. Log:" >&2
    tail -n 40 "${LOG_FILE}" >&2 || true
    exit 1
  fi
  probe_host="${HOST}"
  if [ "${probe_host}" = "0.0.0.0" ]; then
    probe_host="127.0.0.1"
  fi
  loops=30
  while [ "${loops}" -gt 0 ]; do
    if python3 - "${probe_host}" "${PORT}" >/dev/null 2>&1 <<'PY'
import json
import os
import sys
import urllib.request

host, port = sys.argv[1], sys.argv[2]
request = urllib.request.Request("http://%s:%s/api/v1/status" % (host, port))
token = os.environ.get("KV260_EVENT_API_TOKEN", "")
if token:
    request.add_header("X-KV260-Token", token)
with urllib.request.urlopen(request, timeout=1.0) as response:
    data = json.loads(response.read().decode("utf-8"))
if not data.get("ok"):
    raise SystemExit(1)
PY
    then
      echo "KV260 Event Camera API running pid=${pid} url=http://${HOST}:${PORT}"
      return 0
    fi
    if ! pid_alive "${pid}"; then
      break
    fi
    sleep 0.5
    loops=$((loops - 1))
  done
  echo "KV260 Event Camera API started pid=${pid}, but health check did not become ready. Log:" >&2
  tail -n 60 "${LOG_FILE}" >&2 || true
  exit 1
}

stop_api() {
  pid="$(read_pid)"
  if ! pid_alive "${pid}"; then
    rm -f "${PID_FILE}" 2>/dev/null || true
    echo "KV260 Event Camera API stopped"
    return 0
  fi
  kill "${pid}" >/dev/null 2>&1 || true
  loops=30
  while [ "${loops}" -gt 0 ]; do
    if ! pid_alive "${pid}"; then
      rm -f "${PID_FILE}" 2>/dev/null || true
      echo "KV260 Event Camera API stopped"
      return 0
    fi
    sleep 0.2
    loops=$((loops - 1))
  done
  echo "KV260 Event Camera API pid=${pid} did not stop after TERM; sending KILL"
  kill -9 "${pid}" >/dev/null 2>&1 || true
  rm -f "${PID_FILE}" 2>/dev/null || true
}

status_api() {
  pid="$(read_pid)"
  if pid_alive "${pid}"; then
    echo "running pid=${pid} url=http://${HOST}:${PORT} log=${LOG_FILE}"
  else
    echo "stopped"
  fi
}

case "${1:-}" in
  run)
    run_api
    ;;
  start)
    start_api
    ;;
  stop)
    stop_api
    ;;
  restart)
    stop_api
    start_api
    ;;
  status)
    status_api
    ;;
  tail)
    tail -f "${LOG_FILE}"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
