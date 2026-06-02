#!/usr/bin/env sh
set -eu

if [ -z "${HOME}" ]; then
  HOME="/home/petalinux"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${HOME}/Projects/kria-kv260-starter"
if [ ! -d "${PROJECT_DIR}" ]; then
  PROJECT_DIR="${SCRIPT_DIR}/.."
fi
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"
APP_SCRIPT="${PROJECT_DIR}/scripts/kv260-event-camera-app.sh"
NATIVE_VIEWER_SCRIPT="${PROJECT_DIR}/scripts/kv260-metavision-viewer-toggle.sh"
TRANSFER_SCRIPT="${PROJECT_DIR}/scripts/kv260-file-transfer-gui.sh"
LAUNCHER_NAME="kv260-event-camera.desktop"
NATIVE_LAUNCHER_NAME="kv260-metavision-viewer.desktop"
TRANSFER_LAUNCHER_NAME="kv260-file-transfer.desktop"
OLD_LAUNCHER_NAMES="metavision-event-viewer.desktop metavision-event-recorder.desktop metavision-control-panel.desktop"
APP_NAME="KV260 Event Camera"
APP_COMMENT="Open the KV260 Prophesee event camera viewer with close and raw recording controls."
NATIVE_APP_NAME="Metavision Viewer"
NATIVE_APP_COMMENT="Toggle the native Prophesee Metavision viewer: click once to open, click again to close."
TRANSFER_APP_NAME="KV260 File Transfer"
TRANSFER_APP_COMMENT="Copy files and folders between this KV260 and a LAN host with SSH/SCP."
ICON_PATH="/usr/share/icons/Adwaita/48x48/legacy/camera-video.png"
TRANSFER_ICON_PATH="/usr/share/icons/Adwaita/48x48/places/folder-remote.png"
DESKTOP_DIR="${HOME}/.local/share/applications"
DESKTOP_FILE="${DESKTOP_DIR}/${LAUNCHER_NAME}"
NATIVE_DESKTOP_FILE="${DESKTOP_DIR}/${NATIVE_LAUNCHER_NAME}"
TRANSFER_DESKTOP_FILE="${DESKTOP_DIR}/${TRANSFER_LAUNCHER_NAME}"
HOME_SHORTCUT_DIR="${HOME}/Desktop"
HOME_SHORTCUT="${HOME_SHORTCUT_DIR}/${LAUNCHER_NAME}"
NATIVE_HOME_SHORTCUT="${HOME_SHORTCUT_DIR}/${NATIVE_LAUNCHER_NAME}"
TRANSFER_HOME_SHORTCUT="${HOME_SHORTCUT_DIR}/${TRANSFER_LAUNCHER_NAME}"
ROOT_HOME="/home/root"
ROOT_SHORTCUT_DIR="${ROOT_HOME}/Desktop"
ROOT_SHORTCUT="${ROOT_SHORTCUT_DIR}/${LAUNCHER_NAME}"
NATIVE_ROOT_SHORTCUT="${ROOT_SHORTCUT_DIR}/${NATIVE_LAUNCHER_NAME}"
TRANSFER_ROOT_SHORTCUT="${ROOT_SHORTCUT_DIR}/${TRANSFER_LAUNCHER_NAME}"
SYSTEM_DESKTOP_FILE="/usr/share/applications/${LAUNCHER_NAME}"
NATIVE_SYSTEM_DESKTOP_FILE="/usr/share/applications/${NATIVE_LAUNCHER_NAME}"
TRANSFER_SYSTEM_DESKTOP_FILE="/usr/share/applications/${TRANSFER_LAUNCHER_NAME}"
SUDO_PASSWORD="${KV260_SUDO_PASSWORD:-}"
MODE="install"
DO_GLOBAL=0

usage() {
  cat <<'EOF'
Usage:
  kv260-install-prophesee-desktop.sh [--install|--remove] [--global]

  --install      create local user application launchers (default)
  --remove       remove local user application launchers and old desktop shortcuts
  --global       also create/remove /usr/share/applications launchers
                 (requires root privileges)
  --help         show this help
EOF
}

write_desktop_entry() {
  target="$1"
  entry_kind="${2:-custom}"
  case "${entry_kind}" in
    native)
      entry_name="${NATIVE_APP_NAME}"
      entry_comment="${NATIVE_APP_COMMENT}"
      entry_exec="${NATIVE_VIEWER_SCRIPT}"
      entry_icon="${ICON_PATH}"
      entry_wm_class="metavision_viewer"
      entry_keywords="prophesee;metavision;event;camera;native;viewer;toggle;kv260;"
      ;;
    transfer)
      entry_name="${TRANSFER_APP_NAME}"
      entry_comment="${TRANSFER_APP_COMMENT}"
      entry_exec="${TRANSFER_SCRIPT}"
      entry_icon="${TRANSFER_ICON_PATH}"
      entry_wm_class="KV260 File Transfer"
      entry_keywords="kv260;file;transfer;scp;ssh;copy;remote;"
      ;;
    *)
      entry_name="${APP_NAME}"
      entry_comment="${APP_COMMENT}"
      entry_exec="${APP_SCRIPT}"
      entry_icon="${ICON_PATH}"
      entry_wm_class="KV260 Event Camera"
      entry_keywords="prophesee;metavision;event;camera;record;kv260;"
      ;;
  esac
  mkdir -p "$(dirname "${target}")"
  cat > "${target}" <<EOF
[Desktop Entry]
Type=Application
Name=${entry_name}
Comment=${entry_comment}
Path=${PROJECT_DIR}
Exec=${entry_exec}
Icon=${entry_icon}
Terminal=false
Categories=AudioVideo;Science;Utility;
StartupWMClass=${entry_wm_class}
StartupNotify=false
NoDisplay=false
Keywords=${entry_keywords}
EOF
  chmod 755 "${target}"
}

remove_entry() {
  rm -f "${DESKTOP_FILE}" "${HOME_SHORTCUT}" "${NATIVE_DESKTOP_FILE}" "${NATIVE_HOME_SHORTCUT}" "${TRANSFER_DESKTOP_FILE}" "${TRANSFER_HOME_SHORTCUT}"
  for old_name in ${OLD_LAUNCHER_NAMES}; do
    rm -f "${DESKTOP_DIR}/${old_name}" "${HOME_SHORTCUT_DIR}/${old_name}"
  done
  update-desktop-database "${DESKTOP_DIR}" >/dev/null 2>&1 || true
}

install_entry() {
  remove_entry
  if [ "${DO_GLOBAL}" != "1" ]; then
    write_desktop_entry "${DESKTOP_FILE}" custom
    write_desktop_entry "${TRANSFER_DESKTOP_FILE}" transfer
  fi
  update-desktop-database "${DESKTOP_DIR}" >/dev/null 2>&1 || true
}

install_system_entry() {
  tmp_desktop="/tmp/${LAUNCHER_NAME}.$$"
  tmp_transfer_desktop="/tmp/${TRANSFER_LAUNCHER_NAME}.$$"
  write_desktop_entry "${tmp_desktop}" custom
  write_desktop_entry "${tmp_transfer_desktop}" transfer

  if [ "${SUDO_PASSWORD}" ]; then
    printf '%s\n' "${SUDO_PASSWORD}" | sudo -S rm -f "${ROOT_SHORTCUT}" "${NATIVE_ROOT_SHORTCUT}" "${TRANSFER_ROOT_SHORTCUT}" "${NATIVE_SYSTEM_DESKTOP_FILE}" >/dev/null 2>&1 || true
    for old_name in ${OLD_LAUNCHER_NAMES}; do
      printf '%s\n' "${SUDO_PASSWORD}" | sudo -S rm -f "/usr/share/applications/${old_name}" >/dev/null 2>&1 || true
      printf '%s\n' "${SUDO_PASSWORD}" | sudo -S rm -f "${ROOT_SHORTCUT_DIR}/${old_name}" "${ROOT_HOME}/.local/share/applications/${old_name}" >/dev/null 2>&1 || true
    done
    printf '%s\n' "${SUDO_PASSWORD}" | sudo -S install -m 644 "${tmp_desktop}" "${SYSTEM_DESKTOP_FILE}" >/dev/null 2>&1
    printf '%s\n' "${SUDO_PASSWORD}" | sudo -S install -m 644 "${tmp_transfer_desktop}" "${TRANSFER_SYSTEM_DESKTOP_FILE}" >/dev/null 2>&1
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
    rm -f "${tmp_desktop}" "${tmp_transfer_desktop}"
    return 0
  fi

  if [ "$(id -u)" -eq 0 ]; then
    for old_name in ${OLD_LAUNCHER_NAMES}; do
      rm -f "/usr/share/applications/${old_name}"
      rm -f "${ROOT_SHORTCUT_DIR}/${old_name}" "${ROOT_HOME}/.local/share/applications/${old_name}"
    done
    rm -f "${ROOT_SHORTCUT}" "${NATIVE_ROOT_SHORTCUT}" "${TRANSFER_ROOT_SHORTCUT}" "${NATIVE_SYSTEM_DESKTOP_FILE}"
    install -m 644 "${tmp_desktop}" "${SYSTEM_DESKTOP_FILE}"
    install -m 644 "${tmp_transfer_desktop}" "${TRANSFER_SYSTEM_DESKTOP_FILE}"
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
    rm -f "${tmp_desktop}" "${tmp_transfer_desktop}"
    return 0
  fi

  echo "Global install requested but root password not provided."
  echo "Retry with KV260_SUDO_PASSWORD set, or run as root."
  rm -f "${tmp_desktop}" "${tmp_transfer_desktop}"
  return 1
}

remove_system_entry() {
  if [ "${SUDO_PASSWORD}" ]; then
    printf '%s\n' "${SUDO_PASSWORD}" | sudo -S rm -f "${SYSTEM_DESKTOP_FILE}" "${NATIVE_SYSTEM_DESKTOP_FILE}" "${TRANSFER_SYSTEM_DESKTOP_FILE}" >/dev/null 2>&1 || true
    printf '%s\n' "${SUDO_PASSWORD}" | sudo -S rm -f "${ROOT_SHORTCUT}" "${NATIVE_ROOT_SHORTCUT}" "${TRANSFER_ROOT_SHORTCUT}" >/dev/null 2>&1 || true
    for old_name in ${OLD_LAUNCHER_NAMES}; do
      printf '%s\n' "${SUDO_PASSWORD}" | sudo -S rm -f "/usr/share/applications/${old_name}" >/dev/null 2>&1 || true
      printf '%s\n' "${SUDO_PASSWORD}" | sudo -S rm -f "${ROOT_SHORTCUT_DIR}/${old_name}" "${ROOT_HOME}/.local/share/applications/${old_name}" >/dev/null 2>&1 || true
    done
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
    return 0
  fi

  if [ "$(id -u)" -eq 0 ]; then
    rm -f "${SYSTEM_DESKTOP_FILE}" "${NATIVE_SYSTEM_DESKTOP_FILE}" "${TRANSFER_SYSTEM_DESKTOP_FILE}"
    rm -f "${ROOT_SHORTCUT}" "${NATIVE_ROOT_SHORTCUT}" "${TRANSFER_ROOT_SHORTCUT}"
    for old_name in ${OLD_LAUNCHER_NAMES}; do
      rm -f "/usr/share/applications/${old_name}"
      rm -f "${ROOT_SHORTCUT_DIR}/${old_name}" "${ROOT_HOME}/.local/share/applications/${old_name}"
    done
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
    return 0
  fi

  echo "Global remove requested but root password not provided."
  return 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --install)
      MODE="install"
      shift
      ;;
    --remove)
      MODE="remove"
      shift
      ;;
    --global)
      DO_GLOBAL=1
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

if [ "${MODE}" = "install" ]; then
  install_entry
  if [ "${DO_GLOBAL}" = "1" ]; then
    install_system_entry
  fi
  echo "Installed local launcher:"
  [ "${DO_GLOBAL}" != "1" ] && echo "  ${DESKTOP_FILE}"
  [ "${DO_GLOBAL}" != "1" ] && echo "  ${TRANSFER_DESKTOP_FILE}"
  [ "${DO_GLOBAL}" = "1" ] && echo "  ${SYSTEM_DESKTOP_FILE}"
  [ "${DO_GLOBAL}" = "1" ] && echo "  ${TRANSFER_SYSTEM_DESKTOP_FILE}"
else
  remove_entry
  if [ "${DO_GLOBAL}" = "1" ]; then
    remove_system_entry
  fi
  echo "Removed local launcher:"
  echo "  ${DESKTOP_FILE}"
  echo "  ${NATIVE_DESKTOP_FILE}"
  echo "  ${TRANSFER_DESKTOP_FILE}"
  echo "  ${HOME_SHORTCUT}"
  echo "  ${NATIVE_HOME_SHORTCUT}"
  echo "  ${TRANSFER_HOME_SHORTCUT}"
  [ "${DO_GLOBAL}" = "1" ] && echo "  ${SYSTEM_DESKTOP_FILE}"
  [ "${DO_GLOBAL}" = "1" ] && echo "  ${NATIVE_SYSTEM_DESKTOP_FILE}"
  [ "${DO_GLOBAL}" = "1" ] && echo "  ${TRANSFER_SYSTEM_DESKTOP_FILE}"
  [ "${DO_GLOBAL}" = "1" ] && echo "  ${ROOT_SHORTCUT}"
  [ "${DO_GLOBAL}" = "1" ] && echo "  ${NATIVE_ROOT_SHORTCUT}"
  [ "${DO_GLOBAL}" = "1" ] && echo "  ${TRANSFER_ROOT_SHORTCUT}"
fi
