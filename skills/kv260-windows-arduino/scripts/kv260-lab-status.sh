#!/usr/bin/env sh
set -eu

PROJECT_DIR="${KV260_PROJECT_DIR:-/home/petalinux/Projects/kria-kv260-starter}"
WINDOWS_HOST="${KV260_WINDOWS_HOST:-192.168.1.166}"
WINDOWS_USER="${KV260_WINDOWS_USER:-Administrator}"
WINDOWS_KEY="${KV260_WINDOWS_KEY:-/home/petalinux/.ssh/id_dropbear_rsa}"

section() {
  printf '\n== %s ==\n' "$1"
}

section "KV260 identity"
hostname || true
ip -4 addr show scope global || true
ip route || true

section "Disk"
df -h /home/petalinux /home/petalinux/Projects 2>/dev/null || df -h || true

section "Windows reachability"
ping -c 2 "${WINDOWS_HOST}" || true

section "Windows SSH hostname"
if [ -f "${WINDOWS_KEY}" ]; then
  ssh -i "${WINDOWS_KEY}" -y "${WINDOWS_USER}@${WINDOWS_HOST}" \
    "powershell -NoProfile -Command \"hostname\"" || true
else
  echo "missing key: ${WINDOWS_KEY}"
fi

section "KV260 event API"
if [ -x "${PROJECT_DIR}/scripts/kv260-event-camera-api.sh" ]; then
  (cd "${PROJECT_DIR}" && ./scripts/kv260-event-camera-api.sh status) || true
else
  echo "missing ${PROJECT_DIR}/scripts/kv260-event-camera-api.sh"
fi

section "Viewer and /dev/video0"
if [ -x "${PROJECT_DIR}/scripts/kv260-event-camera-switch.sh" ]; then
  (cd "${PROJECT_DIR}" && ./scripts/kv260-event-camera-switch.sh --status) || true
fi
fuser /dev/video0 2>/dev/null || true

section "Related repos"
for repo in polarizer DualLampHI OpenHI3.0 OpenHI2.0; do
  path="/home/petalinux/Projects/${repo}"
  if [ -d "${path}/.git" ]; then
    printf '%s ' "${repo}"
    git -C "${path}" rev-parse --short HEAD
    git -C "${path}" status --short --branch
  else
    echo "${repo}: missing"
  fi
done
