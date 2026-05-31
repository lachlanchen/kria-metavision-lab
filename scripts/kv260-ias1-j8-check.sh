#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
START_VIEWER=0
WITH_PACKAGES=0
SUDO_PASSWORD="${KV260_SUDO_PASSWORD:-${SUDO_PASSWORD:-}}"

usage() {
  cat <<'EOF'
Usage:
  kv260-ias1-j8-check.sh [--start-viewer] [--with-packages]

Checks whether the IAS1/J8 frame camera is exposed as a normal V4L2 frame
device on the current image.

Options:
  --start-viewer    If a non-PSE frame /dev/video node exists, open it.
  --with-packages   Also query dnf package feeds for camera-related packages.
EOF
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

run_root() {
  _cmd="$*"
  if [ "$(id -u)" -eq 0 ]; then
    sh -c "${_cmd}"
    return $?
  fi
  if [ -n "${SUDO_PASSWORD}" ] && has_cmd sudo; then
    printf '%s\n' "${SUDO_PASSWORD}" | sudo -S sh -c "${_cmd}"
    return $?
  fi
  return 1
}

video_format() {
  dev="$1"
  v4l2-ctl -d "${dev}" --all 2>/dev/null | awk -F"'" '/Pixel Format/ { print $2; exit }'
}

is_event_format() {
  fmt="$1"
  case "${fmt}" in
    *PSE*|*pse*|*PSEE*|*psee*) return 0 ;;
  esac
  return 1
}

section() {
  printf '\n===== %s =====\n' "$1"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --start-viewer)
      START_VIEWER=1
      shift
      ;;
    --with-packages)
      WITH_PACKAGES=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

section "Board + kernel"
uname -a
cat /etc/os-release 2>/dev/null | sed -n '1,8p' || true

section "Current V4L2 devices"
frame_node=""
found_video=0
for dev in /dev/video*; do
  [ -e "${dev}" ] || continue
  found_video=1
  fmt="$(video_format "${dev}" || true)"
  driver="$(v4l2-ctl -d "${dev}" --all 2>/dev/null | sed -n '/Driver name/ { s/.*:[[:space:]]*//; p; q }')"
  kind="frame"
  if is_event_format "${fmt}"; then
    kind="event"
  elif [ -z "${frame_node}" ]; then
    frame_node="${dev}"
  fi
  printf '%s kind=%s driver=%s fmt=%s\n' "${dev}" "${kind}" "${driver:-unknown}" "${fmt:-unknown}"
done
[ "${found_video}" = "1" ] || echo "(none)"

section "Current media graph"
for media in /dev/media*; do
  [ -e "${media}" ] || continue
  echo "--- ${media}"
  media-ctl -d "${media}" -p 2>/dev/null | sed -n '1,180p' || true
done

section "AP1302 / AR1335 driver availability"
for mod in ap1302 ar1335 onsemi; do
  echo "--- ${mod}"
  modinfo "${mod}" 2>/dev/null | sed -n '1,40p' || echo "not found as loadable/builtin module"
done

section "Installed firmware overlays"
find /lib/firmware /boot -maxdepth 4 -type f \
  \( -name '*ar1335*' -o -name '*ap1302*' -o -name '*onsemi*' -o -name '*ias*' -o -name '*camera*' -o -name '*kv260*' -o -name '*.dtbo' -o -name '*.bit' -o -name '*.xclbin' \) \
  2>/dev/null | sort | sed -n '1,240p'

section "Loadable apps"
if run_root "xmutil listapps" 2>/dev/null; then
  :
else
  echo "xmutil listapps needs root; set KV260_SUDO_PASSWORD to include this check."
fi

if [ "${WITH_PACKAGES}" = "1" ]; then
  section "Camera package feed search"
  dnf list available '*ar1335*' '*ap1302*' '*onsemi*' '*ias*' '*camera*' '*smartcam*' 2>/dev/null | sed -n '1,220p' || true
fi

section "Conclusion"
if [ -n "${frame_node}" ]; then
  echo "Frame camera node found: ${frame_node}"
  if [ "${START_VIEWER}" = "1" ]; then
    exec "${PROJECT_DIR}/scripts/kv260-camera-viewer.sh" --type frame --video "${frame_node}" --start
  fi
  echo "Open it with:"
  echo "  ${PROJECT_DIR}/scripts/kv260-camera-viewer.sh --type frame --video ${frame_node} --start"
  exit 0
fi

cat <<'EOF'
No non-PSE frame /dev/video node is present.

This means the IAS1/J8 camera is not currently exposed as a normal frame camera
on this booted image. Installing a userspace viewer package will not create the
missing media pipeline. A working no-rebuild path would require an already-built
device-tree/bitstream app for AP1302/AR1335/IAS1 that matches this kernel.
EOF
