#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  kv260-remote-gui-app.sh --list
  kv260-remote-gui-app.sh --check <app-id>
  kv260-remote-gui-app.sh --launch <app-id>

Launches selected KV260 GUI applications through the current X11 DISPLAY.
Use from Windows with SSH X forwarding.
EOF
}

have() {
  command -v "$1" >/dev/null 2>&1
}

app_command() {
  case "$1" in
    pcmanfm) echo "pcmanfm /home/petalinux" ;;
    terminal) echo "matchbox-terminal" ;;
    terminal-rxvt) echo "rxvt" ;;
    editor) echo "l3afpad" ;;
    appearance) echo "matchbox-appearance" ;;
    touch-calibrator) echo "xinput_calibrator" ;;
    preferred-apps) echo "libfm-pref-apps" ;;
    desktop-preferences) echo "pcmanfm --desktop-pref" ;;
    native-metavision) echo "metavision_viewer" ;;
    file-transfer) echo "${PROJECT_DIR}/scripts/kv260-file-transfer-gui.sh" ;;
    *) return 1 ;;
  esac
}

app_name() {
  case "$1" in
    pcmanfm) echo "File Manager PCManFM" ;;
    terminal) echo "Terminal (Matchbox)" ;;
    terminal-rxvt) echo "Terminal (RXVT)" ;;
    editor) echo "L3afpad Text Editor" ;;
    appearance) echo "Appearance" ;;
    touch-calibrator) echo "Calibrate Touchscreen" ;;
    preferred-apps) echo "Preferred Applications" ;;
    desktop-preferences) echo "Desktop Preferences" ;;
    native-metavision) echo "Native Metavision Viewer" ;;
    file-transfer) echo "KV260 File Transfer" ;;
    *) return 1 ;;
  esac
}

app_binary() {
  case "$1" in
    pcmanfm) echo "pcmanfm" ;;
    terminal) echo "matchbox-terminal" ;;
    terminal-rxvt) echo "rxvt" ;;
    editor) echo "l3afpad" ;;
    appearance) echo "matchbox-appearance" ;;
    touch-calibrator) echo "xinput_calibrator" ;;
    preferred-apps) echo "libfm-pref-apps" ;;
    desktop-preferences) echo "pcmanfm" ;;
    native-metavision) echo "metavision_viewer" ;;
    file-transfer) echo "python3" ;;
    *) return 1 ;;
  esac
}

list_apps() {
  for app_id in pcmanfm terminal terminal-rxvt editor appearance touch-calibrator preferred-apps desktop-preferences native-metavision file-transfer; do
    name="$(app_name "${app_id}")"
    cmd="$(app_command "${app_id}")"
    bin="$(app_binary "${app_id}")"
    if have "${bin}"; then
      state="available"
    else
      state="missing"
    fi
    printf '%s\t%s\t%s\t%s\n' "${app_id}" "${state}" "${name}" "${cmd}"
  done
}

check_app() {
  app_id="$1"
  name="$(app_name "${app_id}")" || {
    echo "Unknown app id: ${app_id}" >&2
    return 2
  }
  bin="$(app_binary "${app_id}")"
  cmd="$(app_command "${app_id}")"
  if ! have "${bin}"; then
    echo "${name}: missing required command ${bin}" >&2
    return 3
  fi
  echo "${name}: ${cmd}"
}

launch_app() {
  app_id="$1"
  check_app "${app_id}" >/dev/null
  if [ -z "${DISPLAY:-}" ]; then
    echo "DISPLAY is not set. Use SSH X forwarding from Windows." >&2
    return 4
  fi

  export HOME="${HOME:-/home/petalinux}"
  export USER="${USER:-petalinux}"
  export LOGNAME="${LOGNAME:-${USER}}"
  export LANG=C
  export LC_ALL=C
  export NO_AT_BRIDGE=1

  case "${app_id}" in
    pcmanfm)
      exec pcmanfm /home/petalinux
      ;;
    terminal)
      exec matchbox-terminal
      ;;
    terminal-rxvt)
      exec rxvt
      ;;
    editor)
      exec l3afpad
      ;;
    appearance)
      exec matchbox-appearance
      ;;
    touch-calibrator)
      exec xinput_calibrator
      ;;
    preferred-apps)
      exec libfm-pref-apps
      ;;
    desktop-preferences)
      exec pcmanfm --desktop-pref
      ;;
    native-metavision)
      "${PROJECT_DIR}/scripts/kv260-event-camera-switch.sh" --stop-all >/dev/null 2>&1 || true
      exec metavision_viewer
      ;;
    file-transfer)
      exec "${PROJECT_DIR}/scripts/kv260-file-transfer-gui.sh"
      ;;
  esac
}

case "${1:-}" in
  --list)
    list_apps
    ;;
  --check)
    shift
    [ "$#" -eq 1 ] || {
      usage >&2
      exit 1
    }
    check_app "$1"
    ;;
  --launch)
    shift
    [ "$#" -eq 1 ] || {
      usage >&2
      exit 1
    }
    launch_app "$1"
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
