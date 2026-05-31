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
LAUNCHER_NAME="kv260-event-camera.desktop"
OLD_LAUNCHER_NAMES="metavision-event-viewer.desktop metavision-event-recorder.desktop metavision-control-panel.desktop"
APP_NAME="KV260 Event Camera"
APP_COMMENT="Open the KV260 Prophesee event camera viewer with close and raw recording controls."
ICON_PATH="/usr/share/icons/Adwaita/48x48/legacy/camera-video.png"
DESKTOP_DIR="${HOME}/.local/share/applications"
DESKTOP_FILE="${DESKTOP_DIR}/${LAUNCHER_NAME}"
HOME_SHORTCUT_DIR="${HOME}/Desktop"
HOME_SHORTCUT="${HOME_SHORTCUT_DIR}/${LAUNCHER_NAME}"
ROOT_HOME="/home/root"
ROOT_SHORTCUT_DIR="${ROOT_HOME}/Desktop"
ROOT_SHORTCUT="${ROOT_SHORTCUT_DIR}/${LAUNCHER_NAME}"
SYSTEM_DESKTOP_FILE="/usr/share/applications/${LAUNCHER_NAME}"
SUDO_PASSWORD="${KV260_SUDO_PASSWORD:-}"
MODE="install"
DO_GLOBAL=0

usage() {
  cat <<'EOF'
Usage:
  kv260-install-prophesee-desktop.sh [--install|--remove] [--global]

  --install      create local user launcher + desktop shortcut (default)
  --remove       remove local user launcher + desktop shortcut
  --global       also create/remove /usr/share/applications/kv260-event-camera.desktop
                 (requires root privileges)
  --help         show this help
EOF
}

write_desktop_entry() {
  target="$1"
  mkdir -p "$(dirname "${target}")"
  cat > "${target}" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Comment=${APP_COMMENT}
Path=${PROJECT_DIR}
Exec=${APP_SCRIPT}
Icon=${ICON_PATH}
Terminal=false
Categories=AudioVideo;Science;
StartupWMClass=KV260 Event Camera
StartupNotify=false
NoDisplay=false
Keywords=prophesee;metavision;event;camera;record;kv260;
EOF
  chmod 755 "${target}"
}

remove_entry() {
  rm -f "${DESKTOP_FILE}" "${HOME_SHORTCUT}"
  for old_name in ${OLD_LAUNCHER_NAMES}; do
    rm -f "${DESKTOP_DIR}/${old_name}" "${HOME_SHORTCUT_DIR}/${old_name}"
  done
  update-desktop-database "${DESKTOP_DIR}" >/dev/null 2>&1 || true
}

install_entry() {
  remove_entry
  if [ "${DO_GLOBAL}" != "1" ]; then
    write_desktop_entry "${DESKTOP_FILE}"
  fi
  mkdir -p "${HOME_SHORTCUT_DIR}"
  if [ "${DO_GLOBAL}" = "1" ]; then
    tmp_home_desktop="/tmp/${LAUNCHER_NAME}.home.$$"
    write_desktop_entry "${tmp_home_desktop}"
    cp "${tmp_home_desktop}" "${HOME_SHORTCUT}"
    rm -f "${tmp_home_desktop}"
  else
    cp "${DESKTOP_FILE}" "${HOME_SHORTCUT}"
  fi
  chmod 755 "${HOME_SHORTCUT}"
  update-desktop-database "${DESKTOP_DIR}" >/dev/null 2>&1 || true
}

install_system_entry() {
  tmp_desktop="/tmp/${LAUNCHER_NAME}.$$"
  write_desktop_entry "${tmp_desktop}"

  if [ "${SUDO_PASSWORD}" ]; then
    for old_name in ${OLD_LAUNCHER_NAMES}; do
      printf '%s\n' "${SUDO_PASSWORD}" | sudo -S rm -f "/usr/share/applications/${old_name}" >/dev/null 2>&1 || true
      printf '%s\n' "${SUDO_PASSWORD}" | sudo -S rm -f "${ROOT_SHORTCUT_DIR}/${old_name}" "${ROOT_HOME}/.local/share/applications/${old_name}" >/dev/null 2>&1 || true
    done
    printf '%s\n' "${SUDO_PASSWORD}" | sudo -S install -m 644 "${tmp_desktop}" "${SYSTEM_DESKTOP_FILE}" >/dev/null 2>&1
    if printf '%s\n' "${SUDO_PASSWORD}" | sudo -S test -d "${ROOT_HOME}" >/dev/null 2>&1; then
      printf '%s\n' "${SUDO_PASSWORD}" | sudo -S mkdir -p "${ROOT_SHORTCUT_DIR}" >/dev/null 2>&1 || true
      printf '%s\n' "${SUDO_PASSWORD}" | sudo -S install -m 755 "${tmp_desktop}" "${ROOT_SHORTCUT}" >/dev/null 2>&1 || true
    fi
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
    rm -f "${tmp_desktop}"
    return 0
  fi

  if [ "$(id -u)" -eq 0 ]; then
    for old_name in ${OLD_LAUNCHER_NAMES}; do
      rm -f "/usr/share/applications/${old_name}"
      rm -f "${ROOT_SHORTCUT_DIR}/${old_name}" "${ROOT_HOME}/.local/share/applications/${old_name}"
    done
    install -m 644 "${tmp_desktop}" "${SYSTEM_DESKTOP_FILE}"
    if [ -d "${ROOT_HOME}" ]; then
      mkdir -p "${ROOT_SHORTCUT_DIR}"
      install -m 755 "${tmp_desktop}" "${ROOT_SHORTCUT}"
    fi
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
    rm -f "${tmp_desktop}"
    return 0
  fi

  echo "Global install requested but root password not provided."
  echo "Retry with KV260_SUDO_PASSWORD set, or run as root."
  rm -f "${tmp_desktop}"
  return 1
}

remove_system_entry() {
  if [ "${SUDO_PASSWORD}" ]; then
    printf '%s\n' "${SUDO_PASSWORD}" | sudo -S rm -f "${SYSTEM_DESKTOP_FILE}" >/dev/null 2>&1 || true
    printf '%s\n' "${SUDO_PASSWORD}" | sudo -S rm -f "${ROOT_SHORTCUT}" >/dev/null 2>&1 || true
    for old_name in ${OLD_LAUNCHER_NAMES}; do
      printf '%s\n' "${SUDO_PASSWORD}" | sudo -S rm -f "/usr/share/applications/${old_name}" >/dev/null 2>&1 || true
      printf '%s\n' "${SUDO_PASSWORD}" | sudo -S rm -f "${ROOT_SHORTCUT_DIR}/${old_name}" "${ROOT_HOME}/.local/share/applications/${old_name}" >/dev/null 2>&1 || true
    done
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
    return 0
  fi

  if [ "$(id -u)" -eq 0 ]; then
    rm -f "${SYSTEM_DESKTOP_FILE}"
    rm -f "${ROOT_SHORTCUT}"
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
  echo "  ${HOME_SHORTCUT}"
  [ "${DO_GLOBAL}" != "1" ] && echo "  ${DESKTOP_FILE}"
  [ "${DO_GLOBAL}" = "1" ] && echo "  ${SYSTEM_DESKTOP_FILE}"
  if [ "${DO_GLOBAL}" = "1" ]; then
    echo "  ${ROOT_SHORTCUT}"
  fi
else
  remove_entry
  if [ "${DO_GLOBAL}" = "1" ]; then
    remove_system_entry
  fi
  echo "Removed local launcher:"
  echo "  ${DESKTOP_FILE}"
  echo "  ${HOME_SHORTCUT}"
  [ "${DO_GLOBAL}" = "1" ] && echo "  ${SYSTEM_DESKTOP_FILE}"
  [ "${DO_GLOBAL}" = "1" ] && echo "  ${ROOT_SHORTCUT}"
fi
