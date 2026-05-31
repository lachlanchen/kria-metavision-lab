#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_DIR}"
echo "Stopping previous Metavision viewer session..."
./scripts/kv260-event-visual-gui-local.sh --stop --force >/dev/null 2>&1 || true
sleep 1
if [ -n "${KV260_SUDO_PASSWORD-}" ]; then
  export SUDO_PASSWORD="${KV260_SUDO_PASSWORD}"
fi

echo "Restarting Metavision viewer in strict low-latency mode..."
./scripts/kv260-event-visual-gui-local.sh --start --force --low-latency --no-record --rearm

echo "Current status:"
./scripts/kv260-event-visual-gui-local.sh --status
