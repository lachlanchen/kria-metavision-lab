#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

SUDO_PASSWORD="${KV260_SUDO_PASSWORD:-}"
INSTALL_PACKAGES=1
INSTALL_LAUNCHERS=1
GLOBAL_LAUNCHERS=1
ENABLE_SERVICES=1
SET_NEVER_SLEEP=1
INSTALL_NCDU=1
LOAD_CAMERA_STACK=1
RUN_VALIDATION=1
WINDOWS_SETUP=0
WINDOWS_HOST="${KV260_WINDOWS_HOST:-}"
WINDOWS_USER="${KV260_WINDOWS_USER:-}"
WINDOWS_KEY="${KV260_WINDOWS_KEY:-}"
WINDOWS_DEST="${KV260_WINDOWS_DEST:-}"
WINDOWS_BOARD_ALIAS="${KV260_WINDOWS_BOARD_ALIAS:-petalinux-kv260}"
WINDOWS_DIRECT_SHORTCUTS=0
DRY_RUN=0

log() {
  printf '[kv260-setup] %s\n' "$*"
}

warn() {
  printf '[kv260-setup] WARN: %s\n' "$*" >&2
}

die() {
  printf '[kv260-setup] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  ./scripts/kv260-full-setup.sh [options]

Board setup:
  --sudo-password PASS          Use PASS for sudo -S operations.
  --skip-packages               Do not install target packages with dnf.
  --skip-launchers              Do not install KV260 desktop/menu launchers.
  --no-global-launchers         Install only per-user launchers.
  --skip-services               Do not enable/start dropbear.socket or xserver-nodm.
  --skip-never-sleep            Do not install display never-sleep helper.
  --skip-ncdu                   Do not install the local ncdu-lite helper.
  --skip-camera-load            Do not run the Prophesee camera stack loader.
  --skip-validation             Do not run the event camera validation script.

Windows control center, optional:
  --windows-host HOST           Windows SSH host/IP.
  --windows-user USER           Windows SSH user.
  --windows-key PATH            SSH private key for Windows login.
  --windows-dest PATH           Windows install folder, default:
                                C:/Users/<USER>/Projects/petalinux/kv260-remote-gui
  --windows-board-alias ALIAS   Board SSH alias used by Windows shortcuts.
                                Default: petalinux-kv260
  --windows-direct-shortcuts    Also create direct board/X11 shortcuts.

Other:
  --dry-run                     Print commands without modifying the system.
  -h, --help                    Show this help.

Examples:
  KV260_SUDO_PASSWORD=mdmd ./scripts/kv260-full-setup.sh

  ./scripts/kv260-full-setup.sh \
    --sudo-password mdmd \
    --windows-host 192.168.1.166 \
    --windows-user Administrator \
    --windows-key /home/petalinux/.ssh/id_dropbear_rsa

Password-based Windows SSH also works interactively if no --windows-key is given.
For non-interactive password auth, install sshpass and set SSHPASS or KV260_WINDOWS_SSH_PASSWORD.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --sudo-password)
      [ "$#" -ge 2 ] || die "--sudo-password expects a value"
      SUDO_PASSWORD="$2"
      shift 2
      ;;
    --skip-packages)
      INSTALL_PACKAGES=0
      shift
      ;;
    --skip-launchers)
      INSTALL_LAUNCHERS=0
      shift
      ;;
    --no-global-launchers)
      GLOBAL_LAUNCHERS=0
      shift
      ;;
    --skip-services)
      ENABLE_SERVICES=0
      shift
      ;;
    --skip-never-sleep)
      SET_NEVER_SLEEP=0
      shift
      ;;
    --skip-ncdu)
      INSTALL_NCDU=0
      shift
      ;;
    --skip-camera-load)
      LOAD_CAMERA_STACK=0
      shift
      ;;
    --skip-validation)
      RUN_VALIDATION=0
      shift
      ;;
    --windows-host)
      [ "$#" -ge 2 ] || die "--windows-host expects a value"
      WINDOWS_HOST="$2"
      WINDOWS_SETUP=1
      shift 2
      ;;
    --windows-user)
      [ "$#" -ge 2 ] || die "--windows-user expects a value"
      WINDOWS_USER="$2"
      WINDOWS_SETUP=1
      shift 2
      ;;
    --windows-key)
      [ "$#" -ge 2 ] || die "--windows-key expects a path"
      WINDOWS_KEY="$2"
      WINDOWS_SETUP=1
      shift 2
      ;;
    --windows-dest)
      [ "$#" -ge 2 ] || die "--windows-dest expects a value"
      WINDOWS_DEST="$2"
      WINDOWS_SETUP=1
      shift 2
      ;;
    --windows-board-alias)
      [ "$#" -ge 2 ] || die "--windows-board-alias expects a value"
      WINDOWS_BOARD_ALIAS="$2"
      WINDOWS_SETUP=1
      shift 2
      ;;
    --windows-direct-shortcuts)
      WINDOWS_DIRECT_SHORTCUTS=1
      WINDOWS_SETUP=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

run() {
  log "+ $*"
  if [ "${DRY_RUN}" = "0" ]; then
    "$@"
  fi
}

run_sh() {
  log "+ $*"
  if [ "${DRY_RUN}" = "0" ]; then
    sh -c "$*"
  fi
}

have() {
  command -v "$1" >/dev/null 2>&1
}

run_priv() {
  if [ "$(id -u)" -eq 0 ]; then
    run "$@"
    return
  fi

  if have sudo; then
    log "+ sudo $*"
    if [ "${DRY_RUN}" = "1" ]; then
      return
    fi
    if [ -n "${SUDO_PASSWORD}" ]; then
      printf '%s\n' "${SUDO_PASSWORD}" | sudo -S "$@"
    else
      sudo "$@"
    fi
    return
  fi

  die "root privileges required for: $*"
}

run_priv_sh() {
  if [ "$(id -u)" -eq 0 ]; then
    run_sh "$*"
    return
  fi

  if have sudo; then
    log "+ sudo sh -c $*"
    if [ "${DRY_RUN}" = "1" ]; then
      return
    fi
    if [ -n "${SUDO_PASSWORD}" ]; then
      printf '%s\n' "${SUDO_PASSWORD}" | sudo -S sh -c "$*"
    else
      sudo sh -c "$*"
    fi
    return
  fi

  die "root privileges required for: $*"
}

ensure_dirs() {
  log "Preparing project directories"
  run mkdir -p \
    "${PROJECT_DIR}/recordings/event-camera" \
    "${PROJECT_DIR}/recordings/event-visual" \
    "${PROJECT_DIR}/references" \
    "${HOME:-/home/petalinux}/.cache/kv260-event-camera"
}

ensure_script_modes() {
  log "Ensuring local helper scripts are executable"
  if [ "${DRY_RUN}" = "1" ]; then
    log "+ chmod +x scripts/*.sh scripts/*.py"
    return
  fi
  find "${SCRIPT_DIR}" -maxdepth 1 \( -name '*.sh' -o -name '*.py' \) -type f -exec chmod +x {} +
}

install_one_package() {
  pkg="$1"
  if have rpm && rpm -q "${pkg}" >/dev/null 2>&1; then
    log "Package already installed: ${pkg}"
    return 0
  fi
  if ! have dnf; then
    warn "dnf not found; cannot install ${pkg}"
    return 0
  fi
  if [ "$(id -u)" -eq 0 ]; then
    log "+ dnf -y install ${pkg}"
    [ "${DRY_RUN}" = "1" ] || dnf -y install "${pkg}" || warn "Could not install ${pkg}; package may be absent from this feed."
    return 0
  fi
  if have sudo; then
    log "+ sudo dnf -y install ${pkg}"
    if [ "${DRY_RUN}" = "1" ]; then
      return 0
    fi
    if [ -n "${SUDO_PASSWORD}" ]; then
      printf '%s\n' "${SUDO_PASSWORD}" | sudo -S dnf -y install "${pkg}" || warn "Could not install ${pkg}; package may be absent from this feed."
    else
      sudo dnf -y install "${pkg}" || warn "Could not install ${pkg}; package may be absent from this feed."
    fi
    return 0
  fi
  warn "No sudo available; cannot install ${pkg}"
}

install_packages() {
  [ "${INSTALL_PACKAGES}" = "1" ] || return 0
  log "Installing best-effort GUI/runtime packages from the target feed"
  for pkg in \
    matchbox-desktop \
    matchbox-terminal \
    matchbox-wm \
    matchbox-session-sato \
    pcmanfm \
    l3afpad \
    rxvt \
    xinput-calibrator \
    xauth \
    v4l-utils \
    python3-numpy \
    python3-pillow \
    python3-pygobject
  do
    install_one_package "${pkg}"
  done
}

enable_service_if_present() {
  service="$1"
  if ! have systemctl; then
    warn "systemctl not found; cannot enable ${service}"
    return 0
  fi
  if ! systemctl list-unit-files "${service}" >/dev/null 2>&1; then
    warn "service not known to systemd: ${service}"
    return 0
  fi
  run_priv systemctl enable --now "${service}" || warn "Could not enable/start ${service}"
}

enable_services() {
  [ "${ENABLE_SERVICES}" = "1" ] || return 0
  log "Enabling board SSH and local X desktop services when present"
  enable_service_if_present dropbear.socket
  enable_service_if_present xserver-nodm.service
}

install_never_sleep() {
  [ "${SET_NEVER_SLEEP}" = "1" ] || return 0
  log "Installing local display never-sleep helper"
  if [ "${DRY_RUN}" = "1" ]; then
    log "+ install generated helper /usr/local/bin/kv260-disable-display-sleep.sh"
    log "+ mkdir -p /etc/xdg/autostart"
    log "+ install generated autostart /etc/xdg/autostart/kv260-disable-display-sleep.desktop"
    return 0
  fi

  tmp_script="/tmp/kv260-disable-display-sleep.sh.$$"
  tmp_desktop="/tmp/kv260-disable-display-sleep.desktop.$$"
  cat > "${tmp_script}" <<'EOF'
#!/bin/sh
export DISPLAY="${DISPLAY:-:0}"
if [ -z "${XAUTHORITY:-}" ]; then
  if [ -r "$HOME/.Xauthority" ]; then
    export XAUTHORITY="$HOME/.Xauthority"
  elif [ -r /home/petalinux/.Xauthority ]; then
    export XAUTHORITY=/home/petalinux/.Xauthority
  fi
fi
if command -v xset >/dev/null 2>&1; then
  xset s off >/dev/null 2>&1 || true
  xset s noblank >/dev/null 2>&1 || true
  xset -dpms >/dev/null 2>&1 || true
fi
exit 0
EOF
  cat > "${tmp_desktop}" <<'EOF'
[Desktop Entry]
Type=Application
Name=KV260 Disable Display Sleep
Exec=/usr/local/bin/kv260-disable-display-sleep.sh
Terminal=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
  run_priv install -m 755 "${tmp_script}" /usr/local/bin/kv260-disable-display-sleep.sh
  run_priv mkdir -p /etc/xdg/autostart
  run_priv install -m 644 "${tmp_desktop}" /etc/xdg/autostart/kv260-disable-display-sleep.desktop
  rm -f "${tmp_script}" "${tmp_desktop}"
  /usr/local/bin/kv260-disable-display-sleep.sh >/dev/null 2>&1 || true
}

install_ncdu_lite() {
  [ "${INSTALL_NCDU}" = "1" ] || return 0
  if [ ! -f "${SCRIPT_DIR}/kv260-ncdu-lite.py" ]; then
    warn "Missing ${SCRIPT_DIR}/kv260-ncdu-lite.py"
    return 0
  fi
  log "Installing local ncdu-lite helper as /usr/local/bin/ncdu"
  run_priv install -m 755 "${SCRIPT_DIR}/kv260-ncdu-lite.py" /usr/local/bin/ncdu
}

load_camera_stack() {
  [ "${LOAD_CAMERA_STACK}" = "1" ] || return 0
  if command -v load-prophesee-kv260-imx636.sh >/dev/null 2>&1; then
    log "Loading Prophesee KV260 IMX636 stack"
    run_priv load-prophesee-kv260-imx636.sh || warn "Camera stack loader returned non-zero"
  else
    log "Camera stack loader not found; assuming image already loads the stack or validation will report the issue"
  fi
}

install_launchers() {
  [ "${INSTALL_LAUNCHERS}" = "1" ] || return 0
  log "Installing KV260 desktop/menu launchers"
  if [ "${GLOBAL_LAUNCHERS}" = "1" ]; then
    log "+ KV260_SUDO_PASSWORD=<set> ${SCRIPT_DIR}/kv260-install-prophesee-desktop.sh --install --global"
    if [ "${DRY_RUN}" = "0" ]; then
      KV260_SUDO_PASSWORD="${SUDO_PASSWORD}" "${SCRIPT_DIR}/kv260-install-prophesee-desktop.sh" --install --global
    fi
  else
    run "${SCRIPT_DIR}/kv260-install-prophesee-desktop.sh" --install
  fi
}

validate_board() {
  [ "${RUN_VALIDATION}" = "1" ] || return 0
  log "Running event camera validation"
  run python3 -m py_compile \
    "${SCRIPT_DIR}/kv260-event-camera-app.py" \
    "${SCRIPT_DIR}/kv260-metavision-control-panel.py" \
    "${SCRIPT_DIR}/kv260-validate-event-camera.py"
  run "${SCRIPT_DIR}/kv260-validate-event-camera.py"
}

ssh_base_args() {
  if [ -n "${WINDOWS_KEY}" ]; then
    printf '%s\n' "-i"
    printf '%s\n' "${WINDOWS_KEY}"
  fi
}

windows_run() {
  remote_cmd="$1"
  target="${WINDOWS_USER}@${WINDOWS_HOST}"
  if [ -n "${KV260_WINDOWS_SSH_PASSWORD:-${SSHPASS:-}}" ] && have sshpass; then
    pass="${KV260_WINDOWS_SSH_PASSWORD:-${SSHPASS:-}}"
    log "+ sshpass ssh ${target} ${remote_cmd}"
    if [ "${DRY_RUN}" = "0" ]; then
      SSHPASS="${pass}" sshpass -e ssh -o StrictHostKeyChecking=no "${target}" "${remote_cmd}"
    fi
    return
  fi
  args=()
  while IFS= read -r item; do args+=("${item}"); done < <(ssh_base_args)
  log "+ ssh ${args[*]:-} ${target} ${remote_cmd}"
  if [ "${DRY_RUN}" = "0" ]; then
    ssh "${args[@]}" "${target}" "${remote_cmd}"
  fi
}

windows_copy_file() {
  local_file="$1"
  remote_path="$2"
  target="${WINDOWS_USER}@${WINDOWS_HOST}:${remote_path}"
  if [ -n "${KV260_WINDOWS_SSH_PASSWORD:-${SSHPASS:-}}" ] && have sshpass; then
    pass="${KV260_WINDOWS_SSH_PASSWORD:-${SSHPASS:-}}"
    log "+ sshpass scp ${local_file} ${target}"
    if [ "${DRY_RUN}" = "0" ]; then
      SSHPASS="${pass}" sshpass -e scp -o StrictHostKeyChecking=no "${local_file}" "${target}"
    fi
    return
  fi
  args=()
  while IFS= read -r item; do args+=("${item}"); done < <(ssh_base_args)
  log "+ scp ${args[*]:-} ${local_file} ${target}"
  if [ "${DRY_RUN}" = "0" ]; then
    scp "${args[@]}" "${local_file}" "${target}"
  fi
}

setup_windows_control_center() {
  [ "${WINDOWS_SETUP}" = "1" ] || return 0
  [ -n "${WINDOWS_HOST}" ] || die "--windows-host is required for Windows setup"
  [ -n "${WINDOWS_USER}" ] || die "--windows-user is required for Windows setup"
  if [ -z "${WINDOWS_DEST}" ]; then
    WINDOWS_DEST="C:/Users/${WINDOWS_USER}/Projects/petalinux/kv260-remote-gui"
  fi

  log "Installing Windows KV260 Control Center on ${WINDOWS_USER}@${WINDOWS_HOST}:${WINDOWS_DEST}"
  if [ -n "${KV260_WINDOWS_SSH_PASSWORD:-${SSHPASS:-}}" ] && ! have sshpass; then
    warn "A Windows SSH password was provided, but sshpass is not installed. Falling back to interactive ssh/scp password prompts."
  fi

  windows_run "powershell -NoProfile -ExecutionPolicy Bypass -Command \"New-Item -ItemType Directory -Force -Path '${WINDOWS_DEST}' | Out-Null\""
  for file in "${SCRIPT_DIR}"/windows/*; do
    [ -f "${file}" ] || continue
    windows_copy_file "${file}" "${WINDOWS_DEST}/"
  done

  installer="${WINDOWS_DEST}/Install-KV260WindowsShortcuts.ps1"
  install_args="-HostAlias '${WINDOWS_BOARD_ALIAS}'"
  if [ "${WINDOWS_DIRECT_SHORTCUTS}" = "1" ]; then
    install_args="${install_args} -InstallDirectShortcuts"
  fi
  windows_run "powershell -NoProfile -ExecutionPolicy Bypass -File '${installer}' ${install_args}"
  windows_run "powershell -NoProfile -ExecutionPolicy Bypass -File '${WINDOWS_DEST}/Open-KV260EventCamera.ps1' -HostAlias '${WINDOWS_BOARD_ALIAS}' -CheckOnly"
}

print_summary() {
  cat <<EOF

[kv260-setup] Complete.

Project:
  ${PROJECT_DIR}

Board launchers:
  KV260 Event Camera
  Metavision Viewer

Recording folder:
  ${PROJECT_DIR}/recordings/event-camera

Validate again:
  cd ${PROJECT_DIR}
  ./scripts/kv260-validate-event-camera.py

Open on board display:
  ./scripts/kv260-event-camera-switch.sh --board

Stop all viewers:
  ./scripts/kv260-event-camera-switch.sh --stop-all

EOF
}

log "Starting KV260 full setup"
log "Project: ${PROJECT_DIR}"

ensure_dirs
ensure_script_modes
install_packages
enable_services
install_never_sleep
install_ncdu_lite
load_camera_stack
install_launchers
setup_windows_control_center
validate_board
print_summary
