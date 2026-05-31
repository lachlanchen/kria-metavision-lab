#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [ -z "${HOME}" ]; then
  HOME="/home/petalinux"
fi
SUDO_PASSWORD="${KV260_SUDO_PASSWORD:-${SUDO_PASSWORD:-}}"
LAUNCHER_NAME="kv260-event-camera.desktop"
LOCAL_LAUNCHERS_DIR="${HOME}/.local/share/applications"
DESKTOP_SHORTCUT_DIR="${HOME}/Desktop"
SYSTEM_LAUNCHERS_DIR="/usr/share/applications"
INSTALL_HELPER="${PROJECT_DIR}/scripts/kv260-install-prophesee-desktop.sh"

PRUNE_ONLY=0
RUN_LAUNCH=0
VERBOSE=1

usage() {
  cat <<'EOF'
Usage:
  kv260-fix-metavision-launcher.sh [--prune-only] [--start] [--quiet]

  --prune-only  only remove legacy launchers (no reinstall)
  --start       start the custom KV260 Event Camera app once after repair
  --quiet       reduce output and write a compact status line
EOF
}

is_launcher_candidate() {
  candidate="$1"

  [ -f "${candidate}" ] || return 1
  base="$(basename "${candidate}")"

  [ "${base}" = "${LAUNCHER_NAME}" ] && return 1
  case "${base}" in
    metavision-event-viewer.desktop|metavision-event-recorder.desktop|metavision-control-panel.desktop)
      return 0
      ;;
  esac
  if grep -qi '^Name=.*Metavision Event Viewer' "${candidate}" 2>/dev/null; then
    return 0
  fi
  case "${base}" in
    *metavision*viewer*.desktop|*prophesee*viewer*.desktop|*metavision*.desktop|*prophesee*.desktop)
      return 0
      ;;
  esac
  return 1
}

prune_dir() {
  target_dir="$1"
  [ -d "${target_dir}" ] || return 0
  if ! [ -w "${target_dir}" ]; then
    if [ -n "${SUDO_PASSWORD}" ]; then
      find "${target_dir}" -maxdepth 1 -type f -name '*.desktop' 2>/dev/null |
        while IFS= read -r launcher; do
          if is_launcher_candidate "${launcher}"; then
            printf '%s\n' "${SUDO_PASSWORD}" | sudo -S rm -f "${launcher}" >/dev/null 2>&1 || true
          fi
        done
    fi
    return 0
  fi

  find "${target_dir}" -maxdepth 1 -type f -name '*.desktop' 2>/dev/null |
    while IFS= read -r launcher; do
      if is_launcher_candidate "${launcher}"; then
        if [ "${VERBOSE}" = "1" ]; then
          echo "Removing legacy launcher: ${launcher}"
        fi
        rm -f "${launcher}"
      fi
    done
}

report_entries() {
  echo "Active launcher candidates:"
  for launcher in "${SYSTEM_LAUNCHERS_DIR}" "${LOCAL_LAUNCHERS_DIR}" "${DESKTOP_SHORTCUT_DIR}"; do
    [ -d "${launcher}" ] || continue
    echo "  ${launcher}:"
    find "${launcher}" -maxdepth 1 -type f -name "${LAUNCHER_NAME}" 2>/dev/null | \
      while IFS= read -r file; do
        echo "    $(basename "${file}")"
      done
    # show any other explicit Metavision entries if present
    find "${launcher}" -maxdepth 1 -type f -name '*.desktop' 2>/dev/null |
      while IFS= read -r file; do
        if is_launcher_candidate "${file}"; then
          echo "    legacy: $(basename "${file}")"
        fi
      done
  done
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --prune-only)
      PRUNE_ONLY=1
      shift
      ;;
    --start)
      RUN_LAUNCH=1
      shift
      ;;
    --quiet)
      VERBOSE=0
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

if [ "${PRUNE_ONLY}" = "1" ] && [ "${RUN_LAUNCH}" = "1" ]; then
  echo "Cannot combine --prune-only with --start."
  exit 1
fi

cd "${PROJECT_DIR}"

prune_dir "${LOCAL_LAUNCHERS_DIR}"
prune_dir "${DESKTOP_SHORTCUT_DIR}"
if [ "$(id -u)" -eq 0 ]; then
  prune_dir "${SYSTEM_LAUNCHERS_DIR}"
else
  prune_dir "${SYSTEM_LAUNCHERS_DIR}" >/dev/null 2>&1 || true
fi

if [ "${PRUNE_ONLY}" = "0" ]; then
  sh "${INSTALL_HELPER}" --remove >/dev/null 2>&1 || true
  if [ "$(id -u)" -eq 0 ] || [ -n "${SUDO_PASSWORD}" ]; then
    KV260_SUDO_PASSWORD="${SUDO_PASSWORD}" sh "${INSTALL_HELPER}" --install --global
  else
    sh "${INSTALL_HELPER}" --install
  fi
  report_entries
  if [ "${RUN_LAUNCH}" = "1" ]; then
    DISPLAY="${DISPLAY:-:0}" setsid -f sh "${SCRIPT_DIR}/kv260-event-camera-app.sh"
  fi
  echo "Repair complete. Use menu icon 'KV260 Event Camera' or: DISPLAY=:0 ./scripts/kv260-event-camera-app.sh"
else
  report_entries
  echo "Prune complete. Reinstall with:"
  echo "  KV260_SUDO_PASSWORD=<password> ./scripts/kv260-install-prophesee-desktop.sh --install --global"
fi
