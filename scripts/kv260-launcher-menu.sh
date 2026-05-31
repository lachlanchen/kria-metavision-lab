#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."
VIEWER_WRAPPER="${PROJECT_DIR}/scripts/kv260-launch-desktop-viewer.sh"

HOME="${HOME:-/home/petalinux}"
if [ ! -d "${HOME}" ]; then
  HOME="/home/petalinux"
fi
export HOME
export XAUTHORITY="${XAUTHORITY:-${HOME}/.Xauthority}"
export DISPLAY="${DISPLAY:-:0}"

exec "${VIEWER_WRAPPER}" --live "$@"
