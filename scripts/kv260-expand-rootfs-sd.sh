#!/usr/bin/env sh
set -eu

SCRIPT_NAME="$(basename "$0")"
BACKUP_DIR="${KV260_ROOTFS_GROW_BACKUP_DIR:-/home/petalinux/SystemMaintenance/backups}"
STATE_FILE="${KV260_ROOTFS_GROW_STATE_FILE:-/home/petalinux/SystemMaintenance/expand-rootfs-sd.state}"
DRY_RUN=0
STATUS_ONLY=0
FREE_PERCENT=100
FREE_PERCENT_SET=0

usage() {
  cat <<'EOF'
Usage:
  kv260-expand-rootfs-sd.sh [--status|--dry-run] [--free-percent N]

Idempotently grow the mounted ext4 root filesystem to fill the SD card.

The script is safe to run:
  - before reboot, to grow the partition table;
  - after reboot, to grow the ext4 filesystem if the kernel needed a reboot;
  - after completion, where it becomes a no-op except for a harmless resize2fs check.

Options:
  --free-percent N  use N percent of the baseline free space after root
                    N must be 1..100. Default: 100
  --status          print current layout and planned action without changing anything
  --dry-run         print commands that would be run without changing anything
  --help            show this help

Examples:
  kv260-expand-rootfs-sd.sh --free-percent 25
  kv260-expand-rootfs-sd.sh --free-percent 50
  kv260-expand-rootfs-sd.sh --free-percent 75
  kv260-expand-rootfs-sd.sh --free-percent 100
EOF
}

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

run_cmd() {
  if [ "${DRY_RUN}" = "1" ]; then
    printf 'DRY-RUN:'
    for arg in "$@"; do
      printf ' %s' "$arg"
    done
    printf '\n'
    return 0
  fi
  "$@"
}

extract_field() {
  field="$1"
  awk -v key="${field}" '
    {
      for (i = 1; i <= NF; i++) {
        gsub(",", "", $i)
        if ($i == key "=" && (i + 1) <= NF) {
          value = $(i + 1)
          gsub(",", "", value)
          print value
          exit
        }
        if (index($i, key "=") == 1) {
          sub(key "=", "", $i)
          print $i
          exit
        }
      }
    }
  '
}

partition_line() {
  disk="$1"
  part="$2"
  sfdisk -d "${disk}" | awk -v part="${part}" '$1 == part { print; exit }'
}

max_partition_end() {
  disk="$1"
  sfdisk -d "${disk}" | awk '
    /^\/dev\// {
      start = ""
      size = ""
      for (i = 1; i <= NF; i++) {
        gsub(",", "", $i)
        if ($i == "start=" && (i + 1) <= NF) start = $(i + 1)
        if ($i == "size=" && (i + 1) <= NF) size = $(i + 1)
        if (index($i, "start=") == 1) { sub("start=", "", $i); start = $i }
        if (index($i, "size=") == 1) { sub("size=", "", $i); size = $i }
      }
      if (start != "" && size != "") {
        end = start + size - 1
        if (end > max) max = end
      }
    }
    END { print max + 0 }
  '
}

device_size_sectors() {
  blockdev --getsz "$1"
}

state_get() {
  key="$1"
  [ -f "${STATE_FILE}" ] || return 0
  awk -F= -v key="${key}" '$1 == key { print $2; exit }' "${STATE_FILE}" 2>/dev/null || true
}

write_state_file() {
  baseline_size="$1"
  baseline_free="$2"
  mkdir -p "$(dirname "${STATE_FILE}")"
  if [ "${DRY_RUN}" = "1" ]; then
    log "DRY-RUN: write baseline state to ${STATE_FILE}"
    return 0
  fi
  {
    printf 'created=%s\n' "$(date -Iseconds)"
    printf 'disk=%s\n' "${DISK}"
    printf 'root_dev=%s\n' "${ROOT_DEV}"
    printf 'part_num=%s\n' "${PART_NUM}"
    printf 'part_start=%s\n' "${PART_START}"
    printf 'baseline_size=%s\n' "${baseline_size}"
    printf 'baseline_free=%s\n' "${baseline_free}"
    printf 'target_percent=%s\n' "${FREE_PERCENT}"
    printf 'disk_sectors=%s\n' "${DISK_SECTORS}"
  } > "${STATE_FILE}"
  chmod 600 "${STATE_FILE}" 2>/dev/null || true
  log "Baseline state: ${STATE_FILE}"
}

load_or_create_baseline() {
  saved_disk="$(state_get disk)"
  saved_root_dev="$(state_get root_dev)"
  saved_part_start="$(state_get part_start)"
  saved_baseline_size="$(state_get baseline_size)"
  saved_baseline_free="$(state_get baseline_free)"
  saved_target_percent="$(state_get target_percent)"

  if [ -n "${saved_disk}" ] || [ -n "${saved_root_dev}" ] || [ -n "${saved_part_start}" ] || [ -n "${saved_baseline_size}" ]; then
    if [ "${saved_disk}" = "${DISK}" ] \
      && [ "${saved_root_dev}" = "${ROOT_DEV}" ] \
      && [ "${saved_part_start}" = "${PART_START}" ] \
      && [ -n "${saved_baseline_size}" ] \
      && [ -n "${saved_baseline_free}" ]; then
      BASELINE_SIZE="${saved_baseline_size}"
      BASELINE_FREE="${saved_baseline_free}"
      BASELINE_SOURCE="${STATE_FILE}"
      if [ "${FREE_PERCENT_SET}" = "0" ] && [ -n "${saved_target_percent}" ]; then
        case "${saved_target_percent}" in
          ''|*[!0-9]*) ;;
          *)
            if [ "${saved_target_percent}" -ge 1 ] && [ "${saved_target_percent}" -le 100 ]; then
              FREE_PERCENT="${saved_target_percent}"
            fi
            ;;
        esac
      fi
      if [ "${FREE_PERCENT_SET}" = "1" ] \
        && [ "${STATUS_ONLY}" = "0" ] \
        && [ "${DRY_RUN}" = "0" ] \
        && [ "${saved_target_percent}" != "${FREE_PERCENT}" ]; then
        write_state_file "${BASELINE_SIZE}" "${BASELINE_FREE}"
      fi
      return 0
    fi
    die "baseline state ${STATE_FILE} does not match current root device; move it aside before continuing"
  fi

  BASELINE_SIZE="${PART_SIZE}"
  BASELINE_FREE=$((DISK_SECTORS - PART_START - PART_SIZE))
  BASELINE_SOURCE="current partition table"
  if [ "${STATUS_ONLY}" = "1" ]; then
    BASELINE_SOURCE="current partition table (status only; state not written)"
    return 0
  fi
  write_state_file "${BASELINE_SIZE}" "${BASELINE_FREE}"
}

backup_partition_table() {
  disk="$1"
  stamp="$(date +%Y%m%d-%H%M%S)"
  mkdir -p "${BACKUP_DIR}"
  backup_file="${BACKUP_DIR}/$(basename "${disk}")-sfdisk-${stamp}.dump"
  if [ "${DRY_RUN}" = "1" ]; then
    log "DRY-RUN: sfdisk -d ${disk} > ${backup_file}"
  else
    sfdisk -d "${disk}" > "${backup_file}"
    chmod 600 "${backup_file}" 2>/dev/null || true
    log "Partition table backup: ${backup_file}"
  fi
}

refresh_kernel_partition_table() {
  disk="$1"
  log "Refreshing kernel partition view..."
  if [ "${DRY_RUN}" = "1" ]; then
    log "DRY-RUN: partprobe ${disk}"
    log "DRY-RUN: partx -u ${disk}"
  else
    partprobe "${disk}" >/dev/null 2>&1 || true
    partx -u "${disk}" >/dev/null 2>&1 || true
    sleep 2
  fi
}

print_status() {
  log "Root source:       ${ROOT_SRC}"
  log "Root filesystem:   ${ROOT_FSTYPE}"
  log "Root partition:    ${ROOT_DEV}"
  log "Disk:              ${DISK}"
  log "Partition number:  ${PART_NUM}"
  log "Disk sectors:      ${DISK_SECTORS}"
  log "Partition start:   ${PART_START}"
  log "Table size:        ${PART_SIZE}"
  log "Table end:         ${PART_END}"
  log "Baseline source:   ${BASELINE_SOURCE}"
  log "Baseline size:     ${BASELINE_SIZE}"
  log "Baseline free:     ${BASELINE_FREE}"
  log "Free percent:      ${FREE_PERCENT}%"
  log "Target end:        ${TARGET_END}"
  log "Target size:       ${TARGET_SIZE}"
  log "Kernel part size:  ${KERNEL_PART_SIZE}"
  df -hT / 2>/dev/null || true
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --status)
      STATUS_ONLY=1
      shift
      ;;
    --free-percent)
      [ "$#" -ge 2 ] || die "--free-percent requires a value"
      FREE_PERCENT="$2"
      FREE_PERCENT_SET=1
      shift 2
      ;;
    --free-percent=*)
      FREE_PERCENT="${1#--free-percent=}"
      FREE_PERCENT_SET=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

case "${FREE_PERCENT}" in
  ''|*[!0-9]*) die "--free-percent must be an integer from 1 to 100" ;;
esac
[ "${FREE_PERCENT}" -ge 1 ] || die "--free-percent must be at least 1"
[ "${FREE_PERCENT}" -le 100 ] || die "--free-percent must be at most 100"

for cmd in findmnt readlink lsblk blockdev sfdisk parted partprobe partx resize2fs awk sed date df; do
  need_cmd "${cmd}"
done

if [ "$(id -u)" -ne 0 ]; then
  log "Re-running with sudo because partition resize needs root."
  set --
  [ "${DRY_RUN}" = "1" ] && set -- "$@" --dry-run
  [ "${STATUS_ONLY}" = "1" ] && set -- "$@" --status
  [ "${FREE_PERCENT_SET}" = "1" ] && set -- "$@" --free-percent "${FREE_PERCENT}"
  exec sudo "$0" "$@"
fi

ROOT_SRC="$(findmnt -n -o SOURCE /)"
ROOT_FSTYPE="$(findmnt -n -o FSTYPE /)"
ROOT_DEV="$(readlink -f "${ROOT_SRC}")"

[ "${ROOT_FSTYPE}" = "ext4" ] || die "root filesystem is ${ROOT_FSTYPE}, expected ext4"
[ -b "${ROOT_DEV}" ] || die "root source is not a block device: ${ROOT_DEV}"

PKNAME="$(lsblk -n -o PKNAME "${ROOT_DEV}" | awk 'NF { print $1; exit }')"
[ -n "${PKNAME}" ] || die "could not determine parent disk for ${ROOT_DEV}"
DISK="/dev/${PKNAME}"
[ -b "${DISK}" ] || die "parent disk is not a block device: ${DISK}"
ROOT_BASE="$(basename "${ROOT_DEV}")"
DISK_BASE="$(basename "${DISK}")"
PART_SUFFIX="${ROOT_BASE#${DISK_BASE}}"
PART_NUM="${PART_SUFFIX#p}"
case "${PART_NUM}" in
  ''|*[!0-9]*) die "could not determine partition number for ${ROOT_DEV}" ;;
esac

PART_LINE="$(partition_line "${DISK}" "${ROOT_DEV}")"
[ -n "${PART_LINE}" ] || die "could not find ${ROOT_DEV} in partition table for ${DISK}"
PART_START="$(printf '%s\n' "${PART_LINE}" | extract_field start)"
PART_SIZE="$(printf '%s\n' "${PART_LINE}" | extract_field size)"
PART_TYPE="$(printf '%s\n' "${PART_LINE}" | extract_field type)"
[ -n "${PART_START}" ] || die "could not parse partition start"
[ -n "${PART_SIZE}" ] || die "could not parse partition size"
[ -n "${PART_TYPE}" ] || PART_TYPE=83

DISK_SECTORS="$(device_size_sectors "${DISK}")"
PART_END=$((PART_START + PART_SIZE - 1))
MAX_END="$(max_partition_end "${DISK}")"
KERNEL_PART_SIZE="$(device_size_sectors "${ROOT_DEV}")"

load_or_create_baseline
TARGET_SIZE=$((BASELINE_SIZE + (BASELINE_FREE * FREE_PERCENT / 100)))
MAX_TARGET_SIZE=$((DISK_SECTORS - PART_START))
[ "${TARGET_SIZE}" -le "${MAX_TARGET_SIZE}" ] || TARGET_SIZE="${MAX_TARGET_SIZE}"
TARGET_END=$((PART_START + TARGET_SIZE - 1))

print_status

if [ "${PART_END}" -lt "${MAX_END}" ]; then
  die "${ROOT_DEV} is not the last partition on ${DISK}; refusing to grow automatically"
fi

if [ "${TARGET_SIZE}" -le "${PART_SIZE}" ]; then
  log "Partition table is already at or beyond the ${FREE_PERCENT}% target."
else
  if [ "${STATUS_ONLY}" = "1" ]; then
    log "Planned action: grow partition ${PART_NUM} from ${PART_SIZE} to ${TARGET_SIZE} sectors."
    exit 0
  fi

  log "Growing partition ${ROOT_DEV} to ${FREE_PERCENT}% of the baseline free-space target."
  backup_partition_table "${DISK}"

  if ! run_cmd parted -s "${DISK}" unit s resizepart "${PART_NUM}" "${TARGET_END}s"; then
    log "parted resizepart failed; trying sfdisk fallback."
    if [ "${DRY_RUN}" = "1" ]; then
      log "DRY-RUN: printf '${PART_START},${TARGET_SIZE},${PART_TYPE}\\n' | sfdisk --no-reread --force -N ${PART_NUM} ${DISK}"
    else
      printf '%s,%s,%s\n' "${PART_START}" "${TARGET_SIZE}" "${PART_TYPE}" \
        | sfdisk --no-reread --force -N "${PART_NUM}" "${DISK}"
    fi
  fi

  refresh_kernel_partition_table "${DISK}"
  if [ "${DRY_RUN}" = "1" ]; then
    log "DRY-RUN: partition table was not changed, so stopping before filesystem resize."
    exit 0
  fi
fi

PART_LINE="$(partition_line "${DISK}" "${ROOT_DEV}")"
PART_SIZE="$(printf '%s\n' "${PART_LINE}" | extract_field size)"
PART_END=$((PART_START + PART_SIZE - 1))
KERNEL_PART_SIZE="$(device_size_sectors "${ROOT_DEV}")"

if [ "${KERNEL_PART_SIZE}" -lt "${PART_SIZE}" ]; then
  log "Partition table is updated, but the running kernel still sees the old partition size."
  log "Reboot the board, then run this same script again."
  exit 0
fi

if [ "${STATUS_ONLY}" = "1" ]; then
  log "Planned action: run resize2fs ${ROOT_DEV} if the ext4 filesystem is not already full size."
  exit 0
fi

log "Growing ext4 filesystem online with resize2fs."
run_cmd resize2fs "${ROOT_DEV}"

log "Final filesystem status:"
df -hT / 2>/dev/null || true
log "Done. It is safe to run ${SCRIPT_NAME} again; it will no-op if already expanded."
