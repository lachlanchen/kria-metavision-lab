#!/usr/bin/env bash
set -euo pipefail

PROJECT_SUBDIR="petalinux-projects"
ROOTFS_CONFIG_REL="project-spec/configs/rootfs_config"
USER_ROOTFSCONFIG_REL="project-spec/meta-user/conf/user-rootfsconfig"

print_usage() {
  cat <<'EOF'
Usage:
  kv260-rdp-setup.sh [options]

Options:
  -w, --workspace PATH     Workspace root (default: parent directory of this script)
  -p, --petalinux-dir PATH Override petalinux project directory
  --skip-matchbox           Do not enable packagegroup-petalinux-matchbox
  --dry-run                 Show planned file edits only
  --generate-target-script  Emit scripts/kv260-rdp-target-commands.sh
  -h, --help               Show this help

Example:
  ./kv260-rdp-setup.sh --workspace ~/Projects/kria-kv260-starter --generate-target-script
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PETALINUX_DIR="${WORKSPACE_DIR}/${PROJECT_SUBDIR}"
SKIP_MATCHBOX=0
DRY_RUN=0
GEN_TARGET_SCRIPT=0

while (( "$#" )); do
  case "$1" in
    -w|--workspace)
      if [[ $# -lt 2 ]]; then
        echo "Error: --workspace expects a path" >&2
        exit 1
      fi
      WORKSPACE_DIR="$2"
      PETALINUX_DIR="${WORKSPACE_DIR}/${PROJECT_SUBDIR}"
      shift 2
      ;;
    -p|--petalinux-dir)
      if [[ $# -lt 2 ]]; then
        echo "Error: --petalinux-dir expects a path" >&2
        exit 1
      fi
      PETALINUX_DIR="$2"
      shift 2
      ;;
    --skip-matchbox)
      SKIP_MATCHBOX=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --generate-target-script)
      GEN_TARGET_SCRIPT=1
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      print_usage
      exit 1
      ;;
  esac
done

ROOTFS_CONFIG="${PETALINUX_DIR}/${ROOTFS_CONFIG_REL}"
USER_ROOTFSCONFIG="${PETALINUX_DIR}/${USER_ROOTFSCONFIG_REL}"

if [[ ! -f "${ROOTFS_CONFIG}" ]]; then
  echo "Error: missing rootfs config: ${ROOTFS_CONFIG}" >&2
  exit 1
fi

if [[ ! -f "${USER_ROOTFSCONFIG}" ]]; then
  echo "Error: missing user-rootfsconfig: ${USER_ROOTFSCONFIG}" >&2
  exit 1
fi

snapshot_file() {
  local file="$1"
  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  cp "${file}" "${file}.pre-rdp-${stamp}"
  echo "[backup] ${file} -> ${file}.pre-rdp-${stamp}"
}

ensure_kconfig_line() {
  local file="$1"
  local token="$2"
  local value="$3"
  local target="${token}=${value}"

  if grep -qE "^${token}=.*$" "${file}"; then
    local current
    current="$(grep -E "^${token}=.*$" "${file}" | head -n1)"
    if [[ "${current}" == "${target}" ]]; then
      echo "[ok] ${file}: ${target} already present"
      return 0
    fi
    if (( DRY_RUN )); then
      echo "[dry-run] ${file}: replace -> ${target}"
      return 0
    fi
    sed -i -E "s#^${token}=.*#${target}#" "${file}"
    echo "[updated] ${file}: ${target}"
    return 0
  fi

  if grep -qE "^# ${token} is not set$" "${file}"; then
    if (( DRY_RUN )); then
      echo "[dry-run] ${file}: enable ${target}"
      return 0
    fi
    awk -v token="${token}" -v target="${target}" '
      $0 == ("# " token " is not set") { print target; next }
      { print }
    ' "${file}" > "${file}.tmp"
    mv "${file}.tmp" "${file}"
    echo "[updated] ${file}: ${target}"
    return 0
  fi

  if (( DRY_RUN )); then
    echo "[dry-run] ${file}: append ${target}"
    return 0
  fi
  echo "${target}" >> "${file}"
  echo "[appended] ${file}: ${target}"
}

ensure_user_rootfs_line() {
  local file="$1"
  local token="$2"

  if grep -qE "^${token}$" "${file}"; then
    echo "[ok] ${file}: ${token} already present"
    return 0
  fi

  if grep -qE "^# ${token} is not set$" "${file}"; then
    if (( DRY_RUN )); then
      echo "[dry-run] ${file}: enable ${token}"
      return 0
    fi
    awk -v token="${token}" '
      $0 == ("# " token " is not set") { print token; next }
      { print }
    ' "${file}" > "${file}.tmp"
    mv "${file}.tmp" "${file}"
    echo "[updated] ${file}: ${token}"
    return 0
  fi

  if (( DRY_RUN )); then
    echo "[dry-run] ${file}: append ${token}"
    return 0
  fi
  echo "${token}" >> "${file}"
  echo "[appended] ${file}: ${token}"
}

if (( DRY_RUN == 0 )); then
  snapshot_file "${ROOTFS_CONFIG}"
  snapshot_file "${USER_ROOTFSCONFIG}"
fi

ensure_kconfig_line "${ROOTFS_CONFIG}" "CONFIG_packagegroup-petalinux-x11" "y"

if (( SKIP_MATCHBOX == 0 )); then
  ensure_kconfig_line "${ROOTFS_CONFIG}" "CONFIG_packagegroup-petalinux-matchbox" "y"
fi

ensure_user_rootfs_line "${USER_ROOTFSCONFIG}" "CONFIG_xrdp"
ensure_user_rootfs_line "${USER_ROOTFSCONFIG}" "CONFIG_xorgxrdp"

cat <<EOF

Next steps:

1) Open rootfs menu and confirm package visibility:
   cd "${PETALINUX_DIR}"
   petalinux-config -c rootfs

2) Rebuild image:
   petalinux-build

3) Reflash and boot KV260.

4) On target:
   systemctl status xrdp
   systemctl status xrdp-sesman

EOF

if (( GEN_TARGET_SCRIPT )); then
  TARGET_SCRIPT="${SCRIPT_DIR}/kv260-rdp-target-commands.sh"
  if (( DRY_RUN )); then
    echo "[dry-run] would create ${TARGET_SCRIPT}"
  else
    if [ "${SCRIPT_DIR}/kv260-rdp-target-commands.sh" != "${TARGET_SCRIPT}" ]; then
      cp "${SCRIPT_DIR}/kv260-rdp-target-commands.sh" "${TARGET_SCRIPT}"
    else
      echo "[skipped] ${TARGET_SCRIPT} already exists and is the generator output."
    fi
    chmod +x "${TARGET_SCRIPT}"
    echo "[created] ${TARGET_SCRIPT}"
  fi
fi

if (( DRY_RUN )); then
  echo "[dry-run] No files modified."
fi
