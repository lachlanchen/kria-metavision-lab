#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

export HOME="${HOME:-/home/petalinux}"
export USER="${USER:-petalinux}"
export LOGNAME="${LOGNAME:-${USER}}"
export LANG="${LANG:-C}"
export LC_ALL="${LC_ALL:-C}"
export NO_AT_BRIDGE=1

exec python3 "${PROJECT_DIR}/scripts/kv260-file-transfer-gui.py" "$@"
