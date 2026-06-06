#!/usr/bin/env sh
set -eu

WINDOWS_HOST="${KV260_WINDOWS_HOST:-192.168.1.166}"
WINDOWS_USER="${KV260_WINDOWS_USER:-Administrator}"
WINDOWS_KEY="${KV260_WINDOWS_KEY:-/home/petalinux/.ssh/id_dropbear_rsa}"

if [ ! -f "${WINDOWS_KEY}" ]; then
  echo "missing Windows SSH key: ${WINDOWS_KEY}" >&2
  exit 1
fi

ssh -i "${WINDOWS_KEY}" -y "${WINDOWS_USER}@${WINDOWS_HOST}" \
  "powershell -NoProfile -Command \"hostname; if (Get-Command arduino-cli -ErrorAction SilentlyContinue) { arduino-cli version; arduino-cli board list } else { Write-Output 'arduino-cli not found on PATH' }\""
