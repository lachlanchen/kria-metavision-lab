#!/usr/bin/env sh
set -eu

WORKDIR="$(cd "$(dirname "$0")" && pwd)"
VIEWER_WRAPPER="${WORKDIR}/kv260-launch-desktop-viewer.sh"

if [ ! -x "${VIEWER_WRAPPER}" ]; then
  echo "ERROR: launcher wrapper missing or not executable: ${VIEWER_WRAPPER}"
  exit 1
fi

exec "${VIEWER_WRAPPER}" --live
