#!/usr/bin/env sh
set -eu

DISPLAY_TARGET=":0"
ACTION="start"
FORCE_START=0
KEEP_CAPTURE_SESSION=0
RECORD=1
REALTIME_MODE=0
NICE_ADJ=0
CPU_MASK=""
SUDO_PASSWORD="${SUDO_PASSWORD:-${KV260_SUDO_PASSWORD:-}}"
STRICT_STREAM_PROBE="${KV260_STRICT_STREAM_PROBE:-0}"
VIDEO_DEVICE="/dev/video0"
SENSOR_DEVICE=""
V4L2_HEAP_CHOICE=""
REARM_CAMERA=0
LEGACY_VIEWER_PID="/tmp/event-visual-viewer.pid"
if [ -z "${HOME}" ]; then
  HOME="/home/petalinux"
fi
export HOME
RUNTIME_DIR="${XDG_RUNTIME_DIR:-${HOME}/.cache/kv260-event-viewer}"
if [ -z "${RUNTIME_DIR}" ] || [ "${RUNTIME_DIR}" = "/tmp" ] || [ "${RUNTIME_DIR}" = "/tmp/" ]; then
  RUNTIME_DIR="${HOME}/.cache/kv260-event-viewer"
fi
mkdir -p "${RUNTIME_DIR}"
chmod 700 "${RUNTIME_DIR}" 2>/dev/null || true
VIEWER_PID="${RUNTIME_DIR}/event-visual-viewer.pid"
VIEWER_LOG="${RUNTIME_DIR}/event-visual-viewer.log"
VIEWER_RAW="${RUNTIME_DIR}/event_visual_gui_demo.raw"
VIEWER_LAUNCH_SCRIPT="${RUNTIME_DIR}/event-visual-viewer-launch.sh"
VIEWER_INPUT_CAMERA_CONFIG=""
VIEWER_BIASES=""
VIEWER_OUTPUT_CAMERA_CONFIG=""
VIEWER_ROI=""
VIEWER_SUBSAMPLING=""

usage() {
  cat <<'EOF'
Usage:
  kv260-event-visual-gui-local.sh [--video /dev/videoX] [--display :0]
                                  [--start|--stop|--status] [--force|--no-force]
                                  [--keep-capture] [--low-latency]
                                  [--no-record|--record] [--nice N]
                                  [--cpu-mask N]

Actions:
  --start      Start (or restart) the native Metavision GUI viewer locally.
  --stop       Stop the viewer process.
  --status     Show viewer + X + capture-session status.
  --force      Kill existing viewer and restart.
  --no-force   Keep existing viewer session; do not restart.

Defaults:
  --display :0

Behavior:
  --start stops the text-only event-visual tmux session by default so it doesn't
  hold /dev/video and block the viewer. Use --keep-capture to skip that stop.

Performance:
  --low-latency   Run in reduced-overhead mode (no recording, NO_AT_BRIDGE disabled,
                  optional X11 tuning, optional GPU-friendly flags).
  --rearm         Re-run the camera overlay/module stack before launch.
  --no-rearm      Skip explicit camera stack reload/rearm.
  --no-record     Start viewer without file recording.
  --record        Start viewer with recording enabled (default).
  --output-file PATH
                 Start viewer with the selected .raw recording output path.
  --input-camera-config PATH
                 Pass a Metavision camera config JSON file to the viewer.
  --biases PATH  Pass a Metavision biases file to the viewer.
  --output-camera-config PATH
                 File path where the viewer can save camera settings.
  --roi VALUE    Hardware ROI value for metavision_viewer, e.g. "0 0 640 480".
  --subsampling VALUE
                 Subsampling value for metavision_viewer, e.g. "2 2".
  --nice N        Set `nice -n N` priority (example: --nice -5).
  --cpu-mask N    Pin viewer process to CPU core list with taskset (example: 0).
EOF
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

v4l2_pixel_format() {
  node="$1"
  v4l2-ctl -d "${node}" --all 2>/dev/null | awk -F"'" '/Pixel Format/ { print $2; exit }'
}

video_supports_pse() {
  _fmt="$1"
  if [ -z "${_fmt}" ]; then
    return 1
  fi
  case "${_fmt}" in
    *PSE*|*pse*|*PSEE*|*psee*) return 0 ;;
  esac
  return 1
}

probe_video_stream_bytes() {
  _node="$1"
  _out="${2:-${RUNTIME_DIR}/event-stream-probe.raw}"
  : >"${_out}"

  if [ ! -e "${_node}" ]; then
    return 1
  fi

  if ! has_cmd v4l2-ctl; then
    return 1
  fi

  if has_cmd timeout; then
    if timeout 4 v4l2-ctl -d "${_node}" --set-parm=30 --stream-mmap --stream-count=2 --stream-to="${_out}" >/dev/null 2>&1; then
      :
    fi
  else
    v4l2-ctl -d "${_node}" --stream-mmap --stream-count=2 --stream-to="${_out}" >/dev/null 2>&1 || true
  fi

  if [ ! -s "${_out}" ]; then
    return 1
  fi
  if [ "$(wc -c < "${_out}")" -lt 16 ]; then
    return 1
  fi
  return 0
}

normalize_display_socket() {
  _raw="${1:-:0}"
  if printf '%s' "${_raw}" | grep -q ":"; then
    _display_num="${_raw##*:}"
  else
    _display_num="${_raw#:}"
  fi
  _display_num="${_display_num%.0}"
  case "${_display_num}" in
    ''|*[!0-9]*)
      _display_num=0
      ;;
  esac
  _normalized_display=":${_display_num}"
  _socket="/tmp/.X11-unix/X${_display_num}"
  if ! [ -S "${_socket}" ]; then
    SOCKET_FALLBACK="$(ls /tmp/.X11-unix/X* 2>/dev/null | head -n 1 || true)"
    if [ -n "${SOCKET_FALLBACK}" ]; then
      _socket="${SOCKET_FALLBACK}"
      _normalized_display=":${SOCKET_FALLBACK##*X}"
    fi
  fi
}

is_pid_alive() {
  pid="$1"
  [ -n "${pid}" ] && ps -p "${pid}" >/dev/null 2>&1
}

is_viewer_pid() {
  pid="$1"
  if ! is_pid_alive "${pid}"; then
    return 1
  fi
  ps -p "${pid}" -o comm= 2>/dev/null | grep -qx "metavision_view"
}

viewer_pids() {
  ps -e -o pid= -o comm= 2>/dev/null | awk '$2 == "metavision_view" || $2 == "metavision_viewer" { print $1 }'
}

has_viewer_process() {
  [ -n "$(viewer_pids | head -n 1)" ]
}

kill_process_with_optional_sudo() {
  _pid="$1"
  _signal="${2:-}"
  if [ -z "${_pid}" ]; then
    return 1
  fi

  if [ -n "${_signal}" ]; then
    if kill "${_signal}" "${_pid}" 2>/dev/null; then
      return 0
    fi
  elif kill "${_pid}" 2>/dev/null; then
    return 0
  fi

  if [ -n "${SUDO_PASSWORD}" ]; then
    if [ -n "${_signal}" ]; then
      printf '%s\n' "${SUDO_PASSWORD}" | sudo -S kill "${_signal}" "${_pid}" >/dev/null 2>&1
    else
      printf '%s\n' "${SUDO_PASSWORD}" | sudo -S kill "${_pid}" >/dev/null 2>&1
    fi
    return $?
  fi
  return 1
}

wait_for_no_viewer_processes() {
  _tries="${1:-3}"
  while [ "${_tries}" -gt 0 ]; do
    if ! has_viewer_process; then
      return 0
    fi
    sleep 1
    _tries=$(( _tries - 1 ))
  done
  ! has_viewer_process
}

kill_viewer_processes() {
  local_kill_exit=1
  for viewer_pid in $(viewer_pids); do
    kill_process_with_optional_sudo "${viewer_pid}" >/dev/null 2>&1 || true
    local_kill_exit=0
  done
  if wait_for_no_viewer_processes 3; then
    return 0
  fi
  for viewer_pid in $(viewer_pids); do
    kill_process_with_optional_sudo "${viewer_pid}" -9 >/dev/null 2>&1 || true
    local_kill_exit=0
  done
  if wait_for_no_viewer_processes 2; then
    return 0
  fi
  if ! has_viewer_process; then
    return 0
  fi
  if has_viewer_process; then
    local_kill_exit=2
  fi
  return ${local_kill_exit}
}

cleanup_stale_state() {
  for stale_pid in \
    "${VIEWER_PID}" \
    "${LEGACY_VIEWER_PID}"; do
    if [ -f "${stale_pid}" ]; then
      _pid="$(cat "${stale_pid}" 2>/dev/null || true)"
      if is_viewer_pid "${_pid}"; then
        kill_process_with_optional_sudo "${_pid}" || true
      fi
      rm -f "${stale_pid}"
    fi
  done

  for stale_log in \
    "${VIEWER_LAUNCH_SCRIPT}" \
    "/tmp/event-visual-viewer-launch.sh"; do
    rm -f "${stale_log}" 2>/dev/null || true
  done
}

resolve_viewer_pid() {
  viewer_pids | head -n 1 || true
}

set_viewer_pid() {
  attempt=0
  while [ "${attempt}" -lt 12 ]; do
    pid="$(resolve_viewer_pid)"
    if [ -n "${pid}" ] && is_pid_alive "${pid}"; then
      echo "${pid}" > "${VIEWER_PID}"
      return 0
    fi
    attempt=$(( attempt + 1 ))
    sleep 0.5
  done
  rm -f "${VIEWER_PID}"
  return 1
}

wait_viewer_stable() {
  if [ ! -f "${VIEWER_PID}" ]; then
    return 1
  fi
  pid="$(cat "${VIEWER_PID}" 2>/dev/null || true)"
  attempt=0
  while [ "${attempt}" -lt 3 ]; do
    sleep 1
    if ! is_viewer_pid "${pid}"; then
      rm -f "${VIEWER_PID}"
      return 1
    fi
    attempt=$(( attempt + 1 ))
  done
  return 0
}

release_video_holders() {
  if [ ! -e "${VIDEO_DEVICE}" ] || ! has_cmd fuser; then
    return 0
  fi

  for holder in $(fuser "${VIDEO_DEVICE}" 2>/dev/null | tr -cs '0-9' '\n' | awk 'NF && $1 ~ /^[0-9]+$/'); do
    [ -z "${holder}" ] && continue
    [ "${holder}" = "$$" ] && continue
    if is_viewer_pid "${holder}"; then
      echo "Releasing camera holder (metavision pid=${holder})."
      kill_process_with_optional_sudo "${holder}" || true
      continue
    fi
    echo "Releasing non-viewer camera holder pid=${holder}."
    kill_process_with_optional_sudo "${holder}" || true
  done
}

has_event_nodes() {
  for node in /dev/video* /dev/media*; do
    [ -e "${node}" ] && return 0
  done
  return 1
}

pick_pse_video_node() {
  for node in /dev/video*; do
    [ -e "${node}" ] || continue
    if echo "$(v4l2_pixel_format "${node}")" | grep -qi "PSE"; then
      echo "${node}"
      return 0
    fi
  done

  for node in /dev/video*; do
    [ -e "${node}" ] || continue
    if [ -r "/sys/class/video4linux/${node##*/}/name" ]; then
      if cat "/sys/class/video4linux/${node##*/}/name" 2>/dev/null | grep -qiE "prophesee|psee|IMX636|imx636|GENX320|genx320|event"; then
        echo "${node}"
        return 0
      fi
    fi
  done
  return 1
}

has_pse_video_node() {
  _pse_node="$(pick_pse_video_node || true)"
  if [ -n "${_pse_node}" ]; then
    VIDEO_DEVICE="${_pse_node}"
    return 0
  fi
  return 1
}

pick_valid_event_video_node() {
  for node in /dev/video*; do
    [ -e "${node}" ] || continue
    _fmt="$(v4l2_pixel_format "${node}" || true)"
    if ! video_supports_pse "${_fmt}"; then
      continue
    fi
    if [ "${STRICT_STREAM_PROBE}" != "1" ]; then
      echo "${node}"
      return 0
    fi
    if probe_video_stream_bytes "${node}" "${RUNTIME_DIR}/event-stream-probe-${node##*/}.raw"; then
      echo "${node}"
      return 0
    fi
  done
  return 1
}

ensure_event_video_readiness() {
  _node="${VIDEO_DEVICE}"
  if [ -z "${_node}" ] || [ ! -e "${_node}" ]; then
    _node="$(pick_pse_video_node || true)"
  fi
  if [ -n "${_node}" ] && [ -e "${_node}" ]; then
    _fmt="$(v4l2_pixel_format "${_node}" || true)"
    if video_supports_pse "${_fmt}"; then
      if [ "${STRICT_STREAM_PROBE}" != "1" ] || probe_video_stream_bytes "${_node}" "${RUNTIME_DIR}/event-stream-probe-${_node##*/}.raw"; then
        VIDEO_DEVICE="${_node}"
        return 0
      fi
    fi
  fi

  repair_media_nodes
  ensure_media0_alias || true
  ensure_media_formats || true

  _node="$(pick_valid_event_video_node || true)"
  if [ -n "${_node}" ] && [ -e "${_node}" ]; then
    VIDEO_DEVICE="${_node}"
    return 0
  fi

  _node="$(pick_pse_video_node || true)"
  if [ -z "${_node}" ] || [ ! -e "${_node}" ]; then
    return 1
  fi

  _fmt="$(v4l2_pixel_format "${_node}" || true)"
  if video_supports_pse "${_fmt}"; then
    if [ "${STRICT_STREAM_PROBE}" != "1" ] || probe_video_stream_bytes "${_node}" "${RUNTIME_DIR}/event-stream-probe-${_node##*/}.raw"; then
      VIDEO_DEVICE="${_node}"
      return 0
    fi
  fi

  return 1
}
pick_prophesee_media_node() {
  for node in /dev/media*; do
    [ -e "${node}" ] || continue
    if media-ctl -d "${node}" -p 2>/dev/null | grep -q "model[[:space:]]*: Prophesee Video Pipeline"; then
      echo "${node}"
      return 0
    fi
  done
  if [ -e /dev/media0 ]; then
    echo "/dev/media0"
    return 0
  fi
  if [ -e /dev/media1 ]; then
    echo "/dev/media1"
    return 0
  fi
  return 1
}

pick_prophesee_sensor_node() {
  for node in /dev/v4l-subdev*; do
    [ -e "${node}" ] || continue
    base_node="${node##*/}"
    name_file="/sys/class/video4linux/${base_node}/name"
    if [ ! -r "${name_file}" ]; then
      continue
    fi
    name="$(cat "${name_file}" 2>/dev/null | tr -d '\n' || true)"
    case "${name}" in
      *imx636*|*IMX636*|*genx320*|*GenX320*|*prophesee*|*Prophesee*|*psee*|*PSEE*)
        echo "${node}"
        return 0
        ;;
    esac
  done

  if [ -e /dev/v4l-subdev3 ]; then
    echo "/dev/v4l-subdev3"
    return 0
  fi

  return 1
}

configure_event_sensor_path() {
  SENSOR_DEVICE="$(pick_prophesee_sensor_node || true)"
  if [ -z "${SENSOR_DEVICE}" ]; then
    return 1
  fi

  SENSOR_POWER_CONTROL="/sys/class/video4linux/${SENSOR_DEVICE##*/}/device/power/control"
  if [ -e "${SENSOR_POWER_CONTROL}" ]; then
    run_as_root "sh -c 'printf \"%s\" \"on\" > \"${SENSOR_POWER_CONTROL}\"'" || true
  fi
  return 0
}

pick_v4l2_heap() {
  if [ ! -d /dev/dma_heap ]; then
    return 1
  fi

  if [ -r /dev/dma_heap/reserved ] && [ -w /dev/dma_heap/reserved ]; then
    echo "reserved"
    return 0
  fi

  for heap_path in /dev/dma_heap/*; do
    [ -e "${heap_path}" ] || continue
    if [ -r "${heap_path}" ] && [ -w "${heap_path}" ]; then
      echo "${heap_path##*/}"
      return 0
    fi
  done

  return 1
}

prepare_event_runtime_env() {
  V4L2_SENSOR_PATH=""
  if configure_event_sensor_path; then
    V4L2_HEAP_CHOICE="$(pick_v4l2_heap || true)"
    [ -n "${V4L2_HEAP_CHOICE}" ] || V4L2_HEAP_CHOICE=""
  else
    V4L2_HEAP_CHOICE=""
  fi
}

ensure_media0_alias() {
  _media_node="$(pick_prophesee_media_node || true)"
  if [ -z "${_media_node}" ]; then
    return 1
  fi

  if [ "${_media_node}" = "/dev/media0" ] && [ -e /dev/media0 ]; then
    return 0
  fi

  if [ -e /dev/media0 ] && [ -L /dev/media0 ]; then
    _current_alias="$(readlink -f /dev/media0 2>/dev/null || true)"
    if [ "${_current_alias}" = "${_media_node}" ]; then
      return 0
    fi
  fi

  if ! run_as_root "ln -sf \"${_media_node}\" /dev/media0"; then
    return 1
  fi
  return 0
}

ensure_media_formats() {
  _media_node="$(pick_prophesee_media_node || true)"
  if [ -z "${_media_node}" ]; then
    return 1
  fi

  if has_pse_video_node; then
    return 0
  fi

  run_as_root "media-ctl -d ${_media_node} -V \"'imx636 6-003c':0[fmt:PSEE_EVT21/1280x720]\" -V \"'a0010000.mipi_csi2_rx_subsystem':1[fmt:PSEE_EVT21ME/1280x720]\" -V \"'a0040000.axis_tkeep_handler':1[fmt:PSEE_EVT21ME/1280x720]\" -V \"'a0050000.event_stream_smart_tra':1[fmt:PSEE_EVT21/1280x720]\""

  # Recheck after format refresh.
  if has_pse_video_node; then
    return 0
  fi

  # Try the older IMX636 token (when media graph entity names differ).
  run_as_root "media-ctl -d ${_media_node} -V \"'imx636 6-003c':0[fmt:PSEE_EVT3/1280x720]\" -V \"'a0010000.mipi_csi2_rx_subsystem':1[fmt:PSEE_EVT3/1280x720]\" -V \"'a0040000.axis_tkeep_handler':1[fmt:PSEE_EVT3/1280x720]\" -V \"'a0050000.event_stream_smart_tra':1[fmt:PSEE_EVT3/1280x720]\""
  if has_pse_video_node; then
    return 0
  fi

  return 1
}

run_as_root() {
  _cmd="$*"
  if [ "$(id -u)" -eq 0 ]; then
    sh -c "${_cmd}"
    return $?
  fi

  if [ -z "${SUDO_PASSWORD}" ] || ! has_cmd sudo; then
    return 1
  fi

  printf '%s\n' "${SUDO_PASSWORD}" | sudo -S sh -c "${_cmd}" >/dev/null 2>&1
  return $?
}

repair_media_nodes() {
  for candidate in /dev/media0 /dev/media1; do
    if [ -L "${candidate}" ] && [ ! -e "${candidate}" ]; then
      rm -f "${candidate}" 2>/dev/null || true
    fi
  done
}

hard_rearm_camera_stack() {
  ensure_media0_alias || true
  for mod in psee_video imx636 psee_event_stream_smart_tracker psee_tkeep_handler ps_host_if psee_csi2rxss psee-csi2rxss; do
    run_as_root "modprobe -r ${mod}" >/dev/null 2>&1 || true
  done

  if has_pse_video_node; then
    return 0
  fi

  for loader in \
    /usr/bin/load-prophesee-kv260-imx636.sh \
    /usr/local/bin/load-prophesee-kv260-imx636.sh \
    /usr/local/sbin/load-prophesee-kv260-imx636.sh \
    /usr/bin/load-prophesee-kv260-genx320.sh \
    /usr/local/bin/load-prophesee-kv260-genx320.sh \
    /usr/local/sbin/load-prophesee-kv260-genx320.sh; do
    if [ -f "${loader}" ]; then
      if run_as_root "bash ${loader}"; then
        sleep 2
      fi
    fi
  done

  for attempt in 1 2 3; do
    ensure_media_formats || true
    if ensure_event_video_readiness; then
      return 0
    fi
    sleep 1
  done

  return 1
}

maybe_reload_camera_stack() {
  if [ "${FORCE_START}" != "1" ] && [ "${REARM_CAMERA}" != "1" ]; then
    return 0
  fi

  for mod in psee_video imx636 psee_event_stream_smart_tracker psee_tkeep_handler ps_host_if psee_csi2rxss psee-csi2rxss; do
    run_as_root "modprobe -r ${mod}" >/dev/null 2>&1 || true
  done

  ensure_media0_alias || true

  for loader in \
    /usr/bin/load-prophesee-kv260-imx636.sh \
    /usr/local/bin/load-prophesee-kv260-imx636.sh \
    /usr/local/sbin/load-prophesee-kv260-imx636.sh \
    /usr/bin/load-prophesee-kv260-genx320.sh \
    /usr/local/bin/load-prophesee-kv260-genx320.sh \
    /usr/local/sbin/load-prophesee-kv260-genx320.sh; do
    if [ -f "${loader}" ]; then
      echo "Reloading camera stack via ${loader}"
      run_as_root "bash ${loader}" && return 0
    fi
  done

  return 1
}

maybe_load_camera_modules() {
  repair_media_nodes || true

  if has_pse_video_node; then
    configure_event_sensor_path || true
    return 0
  fi

  ensure_media0_alias || true
  ensure_media_formats || true
  if has_pse_video_node; then
    configure_event_sensor_path || true
    return 0
  fi

  for loader in \
    /usr/bin/load-prophesee-kv260-imx636.sh \
    /usr/local/bin/load-prophesee-kv260-imx636.sh \
    /usr/local/sbin/load-prophesee-kv260-imx636.sh \
    /usr/bin/load-prophesee-kv260-genx320.sh \
    /usr/local/bin/load-prophesee-kv260-genx320.sh \
    /usr/local/sbin/load-prophesee-kv260-genx320.sh; do
    if [ -f "${loader}" ]; then
      echo "Attempting camera overlay load: ${loader}"
        if run_as_root "bash ${loader}"; then
        sleep 2
          ensure_media_formats || true
          if has_pse_video_node; then
            configure_event_sensor_path || true
            echo "Camera overlay load command succeeded: ${loader}"
            return 0
          fi
        fi
      echo "Overlay loader failed or produced no nodes: ${loader}"
    fi
  done

  if has_cmd modprobe; then
    need_modprobe=0
    for mod in psee_video imx636 psee_event_stream_smart_tracker psee_tkeep_handler ps_host_if psee_csi2rxss psee-csi2rxss; do
      if ! lsmod 2>/dev/null | awk '{print $1}' | grep -qx "${mod}"; then
        need_modprobe=1
      fi
    done

    if [ "${need_modprobe}" -ne 0 ]; then
      echo "Attempting direct module load for Prophesee stack."
      for mod in psee_video imx636 psee_event_stream_smart_tracker psee_tkeep_handler ps_host_if psee_csi2rxss psee-csi2rxss; do
        run_as_root "modprobe ${mod}" || true
      done
      sleep 2
      if has_pse_video_node; then
        configure_event_sensor_path || true
        echo "Prophesee modules loaded."
        return 0
      fi
    fi
  fi

  return 1
}

verify_event_stream() {
  if [ "${FORCE_START}" != "1" ]; then
    return 0
  fi

  attempt=0
  while [ "${attempt}" -lt 8 ]; do
    if grep -q "Camera has been opened successfully" "${VIEWER_LOG}" 2>/dev/null; then
      return 0
    fi
    if grep -q "V4l2DataTransfer - start_impl/run_impl" "${VIEWER_LOG}" 2>/dev/null; then
      return 0
    fi
    attempt=$(( attempt + 1 ))
    sleep 0.5
  done
  return 1
}

notify_failure() {
  message="$1"
  echo "${message}"

  normalize_display_socket "${DISPLAY_TARGET}"
  X_DISPLAY="${_normalized_display}"
  if [ "${DISPLAY:-}" = "" ]; then
    export DISPLAY="${X_DISPLAY}"
  fi
  export XAUTHORITY="${XAUTHORITY:-${HOME}/.Xauthority}"
  if ! [ -S "${_socket}" ]; then
    return 0
  fi
  if has_cmd xmessage; then
    (DISPLAY="${DISPLAY}" XAUTHORITY="${XAUTHORITY}" xmessage -center "${message}" </dev/null >/dev/null 2>&1 &) || true
  elif has_cmd kdialog; then
    (DISPLAY="${DISPLAY}" XAUTHORITY="${XAUTHORITY}" kdialog --msgbox "${message}" </dev/null >/dev/null 2>&1 &) || true
  elif has_cmd zenity; then
    (DISPLAY="${DISPLAY}" XAUTHORITY="${XAUTHORITY}" zenity --error --text "${message}" </dev/null >/dev/null 2>&1 &) || true
  fi
}

write_viewer_launch_script() {
  viewer_cmd="exec /usr/bin/metavision_viewer"
  if [ -n "${VIEWER_INPUT_CAMERA_CONFIG}" ]; then
    viewer_cmd="${viewer_cmd} -j $(shell_quote "${VIEWER_INPUT_CAMERA_CONFIG}")"
  fi
  if [ -n "${VIEWER_BIASES}" ]; then
    viewer_cmd="${viewer_cmd} -b $(shell_quote "${VIEWER_BIASES}")"
  fi
  if [ "${RECORD}" = "1" ]; then
    viewer_cmd="${viewer_cmd} -o $(shell_quote "${VIEWER_RAW}")"
  fi
  if [ -n "${VIEWER_OUTPUT_CAMERA_CONFIG}" ]; then
    viewer_cmd="${viewer_cmd} --output-camera-config $(shell_quote "${VIEWER_OUTPUT_CAMERA_CONFIG}")"
  fi
  if [ -n "${VIEWER_ROI}" ]; then
    viewer_cmd="${viewer_cmd} -r $(shell_quote "${VIEWER_ROI}")"
  fi
  if [ -n "${VIEWER_SUBSAMPLING}" ]; then
    viewer_cmd="${viewer_cmd} -d $(shell_quote "${VIEWER_SUBSAMPLING}")"
  fi

  : > "${VIEWER_LAUNCH_SCRIPT}"
  {
    echo "#!/bin/sh"
    echo "set -eu"
    echo "export DISPLAY=\"${X_DISPLAY}\""
    echo "export XAUTHORITY=\"${XAUTHORITY:-${HOME}/.Xauthority}\""
    [ -n "${V4L2_HEAP_CHOICE}" ] && echo "export V4L2_HEAP=\"${V4L2_HEAP_CHOICE}\""
    [ -n "${SENSOR_DEVICE}" ] && echo "export V4L2_SENSOR_PATH=\"${SENSOR_DEVICE}\""
    echo "export NO_AT_BRIDGE=1"
    echo "export HOME=\"${HOME}\""
    if [ "${REALTIME_MODE}" = "1" ]; then
      echo "export GDK_BACKEND=x11"
      echo "export QT_X11_NO_MITSHM=1"
    fi
    echo "${viewer_cmd}"
  } > "${VIEWER_LAUNCH_SCRIPT}"
  chmod +x "${VIEWER_LAUNCH_SCRIPT}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --display)
      DISPLAY_TARGET="$2"
      shift 2
      ;;
    --video)
      # kept for parity with earlier scripts and remote helper
      shift 2
      ;;
    --start|--stop|--status)
      ACTION="${1#--}"
      shift
      ;;
    --keep-capture)
      KEEP_CAPTURE_SESSION=1
      shift
      ;;
    --force)
      FORCE_START=1
      shift
      ;;
    --no-force)
      FORCE_START=0
      shift
      ;;
    --low-latency)
      REALTIME_MODE=1
      RECORD=0
      NICE_ADJ=0
      shift
      ;;
    --rearm)
      REARM_CAMERA=1
      shift
      ;;
    --no-rearm)
      REARM_CAMERA=0
      shift
      ;;
    --no-record)
      RECORD=0
      shift
      ;;
    --record)
      RECORD=1
      shift
      ;;
    --output-file)
      VIEWER_RAW="$2"
      RECORD=1
      shift 2
      ;;
    --input-camera-config)
      VIEWER_INPUT_CAMERA_CONFIG="$2"
      shift 2
      ;;
    --biases)
      VIEWER_BIASES="$2"
      shift 2
      ;;
    --output-camera-config)
      VIEWER_OUTPUT_CAMERA_CONFIG="$2"
      shift 2
      ;;
    --roi)
      VIEWER_ROI="$2"
      shift 2
      ;;
    --subsampling)
      VIEWER_SUBSAMPLING="$2"
      shift 2
      ;;
    --nice)
      NICE_ADJ="$2"
      shift 2
      ;;
    --cpu-mask)
      CPU_MASK="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

TMUX="tmux -L kv260-event-visual"
SESSION="event-visual"

start_viewer() {
  if [ "${FORCE_START}" != "1" ] && has_viewer_process; then
    current_pid="$(resolve_viewer_pid)"
    if [ -n "${current_pid}" ] && is_viewer_pid "${current_pid}"; then
      echo "${current_pid}" > "${VIEWER_PID}"
      echo "Viewer already running (pid ${current_pid}). Use --force or --recover to restart."
      return 0
    fi
  fi

  if [ "${FORCE_START}" = "1" ]; then
    cleanup_stale_state
    release_video_holders
  fi

  if [ "${KEEP_CAPTURE_SESSION}" != "1" ]; then
    if ${TMUX} has-session -t "${SESSION}" 2>/dev/null; then
      ${TMUX} kill-session -t "${SESSION}" || true
      echo "Stopped capture session: ${SESSION}"
    fi
  fi

  if [ "${REARM_CAMERA}" = "1" ]; then
    maybe_reload_camera_stack || true
  fi
  if ! maybe_load_camera_modules; then
    notify_failure "Prophesee camera not ready. Run load-prophesee-kv260-imx636.sh and retry."
    return 1
  fi
  if ! ensure_event_video_readiness; then
    echo "Event node format/stream probe failed; attempting full pipeline reset."
    hard_rearm_camera_stack || true
    if ! ensure_event_video_readiness; then
      if [ -n "${VIDEO_DEVICE}" ]; then
        echo "No valid event node still detected. Current VIDEO_DEVICE=${VIDEO_DEVICE}"
      fi
      notify_failure "Metavision stream is not available. Prophesee camera pipeline is present but not producing frames."
      return 1
    fi
  fi
  prepare_event_runtime_env

  normalize_display_socket "${DISPLAY_TARGET}"
  X_DISPLAY="${_normalized_display}"
  SOCKET_PATH="${_socket}"
  if [ ! -S "${SOCKET_PATH}" ]; then
    echo "No X socket at ${SOCKET_PATH}. Start Matchbox/X on :0 first."
    return 1
  fi

  if [ -f "${VIEWER_PID}" ]; then
    old_pid="$(cat "${VIEWER_PID}")"
    if is_viewer_pid "${old_pid}"; then
      if [ "${FORCE_START}" = "1" ]; then
        echo "Forcing restart: stopping existing viewer pid ${old_pid}."
        kill_process_with_optional_sudo "${old_pid}" || true
        rm -f "${VIEWER_PID}"
        sleep 1
      else
        echo "Viewer already running (pid ${old_pid}). Use --force to restart."
        return 0
      fi
    else
      rm -f "${VIEWER_PID}"
    fi
  fi
  if has_viewer_process; then
    if [ "${FORCE_START}" = "1" ]; then
      echo "Metavision viewer already running (forcing restart)."
      kill_viewer_processes || true
      sleep 1
    else
      echo "Metavision viewer already running. Use --force to restart."
      return 0
    fi
  fi
  write_viewer_launch_script

  LAUNCH_CMD="sh ${VIEWER_LAUNCH_SCRIPT}"
  if [ -n "${CPU_MASK}" ] && has_cmd taskset; then
    LAUNCH_CMD="taskset -c ${CPU_MASK} ${LAUNCH_CMD}"
  elif [ -n "${CPU_MASK}" ]; then
    echo "taskset not available on target; ignoring --cpu-mask=${CPU_MASK}"
  fi

  if [ "${NICE_ADJ}" -lt 0 ]; then
    echo "Negative priority requested; running with default priority."
    NICE_ADJ=0
  fi
  if [ "${NICE_ADJ}" -ne 0 ] && has_cmd nice; then
    if sh -c "nice -n ${NICE_ADJ} true" >/dev/null 2>&1; then
      LAUNCH_CMD="nice -n ${NICE_ADJ} ${LAUNCH_CMD}"
    else
      echo "nice -n ${NICE_ADJ} is not permitted for this user; running with default priority."
      NICE_ADJ=0
    fi
  fi

  if has_cmd setsid; then
    setsid -f sh -c "${LAUNCH_CMD}" >"${VIEWER_LOG}" 2>&1 < /dev/null
  else
    nohup sh -c "${LAUNCH_CMD}" >"${VIEWER_LOG}" 2>&1 < /dev/null &
  fi
  if ! set_viewer_pid; then
    echo "Viewer process did not stay alive after launch; check ${VIEWER_LOG}."
    return 1
  fi

  if ! verify_event_stream; then
    echo "No immediate stream detected; forcing one full rearm/restart."
    stop_viewer || true
    cleanup_stale_state
    release_video_holders
    maybe_reload_camera_stack || true
    maybe_load_camera_modules || true
    write_viewer_launch_script
    if [ -f "${VIEWER_PID}" ]; then
      rm -f "${VIEWER_PID}"
    fi
    if has_cmd setsid; then
      setsid -f sh -c "${LAUNCH_CMD}" >"${VIEWER_LOG}" 2>&1 < /dev/null
    else
      nohup sh -c "${LAUNCH_CMD}" >"${VIEWER_LOG}" 2>&1 < /dev/null &
    fi
    if ! set_viewer_pid; then
      echo "Viewer failed after retry."
      return 1
    fi
  fi
  if ! wait_viewer_stable; then
    echo "Viewer exited shortly after launch; check ${VIEWER_LOG}."
    return 1
  fi

  MODE_LABEL="recording to ${VIEWER_RAW}"
  [ "${RECORD}" = "0" ] && MODE_LABEL="live only (no recording)"
  echo "Started viewer (pid $(cat "${VIEWER_PID}")). Mode: ${MODE_LABEL}. NICE=${NICE_ADJ}, CPU_MASK=${CPU_MASK:-auto}."
}

stop_viewer() {
  stopped_any=0
  if [ -f "${VIEWER_PID}" ]; then
    pid="$(cat "${VIEWER_PID}")"
    if is_pid_alive "${pid}"; then
      if is_viewer_pid "${pid}"; then
        if kill_process_with_optional_sudo "${pid}"; then
          stopped_any=1
        else
          echo "Could not stop pid ${pid} with available privileges."
        fi
      else
        echo "Ignoring stale PID file content: ${pid} (not a metavision process)."
      fi
    fi
    rm -f "${VIEWER_PID}"
  fi

  if [ "${stopped_any}" = "1" ] && wait_for_no_viewer_processes 3; then
    echo "Stopped metavision viewer."
    return 0
  fi

  if has_viewer_process; then
    if kill_viewer_processes; then
      echo "Stopped metavision viewer."
      rm -f "${VIEWER_PID}"
      return 0
    else
      echo "Some metavision_viewer processes may still be running (permission issue)."
    fi
  fi

  echo "No viewer process found."
  rm -f "${VIEWER_PID}"
}

status_viewer() {
  if [ -f "${VIEWER_PID}" ]; then
    pid="$(cat "${VIEWER_PID}")"
    if is_viewer_pid "${pid}"; then
      echo "Viewer running (pid=${pid})."
    elif is_pid_alive "${pid}"; then
      echo "Viewer pid file points to non-viewer process."
    else
      echo "Viewer pid file exists but process not active."
    fi
  else
    echo "No viewer pid file."
  fi
  for viewer_pid in $(viewer_pids); do
    ps -p "${viewer_pid}" -o pid=,user=,comm=,args= 2>/dev/null || true
  done
  echo "--- capture session ---"
  if ${TMUX} has-session -t "${SESSION}" 2>/dev/null; then
    echo "event-visual tmux session is running."
  else
    echo "No event-visual tmux session."
  fi
  echo "--- X state ---"
  ls -l /tmp/.X11-unix/X* 2>/dev/null || echo "No X socket present."
  echo "--- viewer log tail ---"
  echo "Configured sensor path: ${SENSOR_DEVICE:-<unset>}"
  if [ -n "${VIDEO_DEVICE}" ] && [ -e "${VIDEO_DEVICE}" ]; then
    echo "Event video node: ${VIDEO_DEVICE} (fmt=$(v4l2_pixel_format "${VIDEO_DEVICE}" | tr '\n' ' ' || echo unknown))"
  else
    echo "Event video node: ${VIDEO_DEVICE:-<unset>}"
  fi
  tail -n 30 "${VIEWER_LOG}" 2>/dev/null || true
}

case "${ACTION}" in
  start)
    start_viewer
    ;;
  stop)
    stop_viewer
    ;;
  status)
    status_viewer
    ;;
  *)
    echo "Unknown action: ${ACTION}"
    exit 1
    ;;
esac
