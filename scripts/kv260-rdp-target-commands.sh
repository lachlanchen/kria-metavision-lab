#!/usr/bin/env sh
set -eu

show_usage() {
  cat <<'EOF'
Usage:
  kv260-rdp-target-commands.sh [options] <kv260-ip-or-host> [username]
  kv260-rdp-target-commands.sh --local [options]

Options:
  --local                Run checks/services on the local target (no SSH).
  --repair-startwm       Create /etc/xrdp/startwm.sh if it is missing or lacks Xsession.
  --skip-service-restart  Skip enabling/restarting xrdp services (checks only).
  -h, --help             Show help.

Examples:
  kv260-rdp-target-commands.sh <kv260-ip> root
  kv260-rdp-target-commands.sh --local --repair-startwm
EOF
}

LOCAL_MODE=0
REPAIR_STARTWM=0
SKIP_SERVICE_RESTART=0
BOARD=""
USER="root"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --local)
      LOCAL_MODE=1
      shift
      ;;
    --repair-startwm)
      REPAIR_STARTWM=1
      shift
      ;;
    --skip-service-restart)
      SKIP_SERVICE_RESTART=1
      shift
      ;;
    -h|--help)
      show_usage
      exit 0
      ;;
    --*)
      echo "Unknown option: $1"
      show_usage
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

if [ "${LOCAL_MODE}" -eq 0 ]; then
  if [ "$#" -lt 1 ]; then
    if [ -n "${KV260_BOARD_IP:-}" ]; then
      BOARD="${KV260_BOARD_IP}"
    else
      echo "Usage: $0 <kv260-ip-or-host> [username]  (or pass --local)"
      exit 1
    fi
  else
    BOARD="$1"
    shift || true
  fi

  if [ "$#" -gt 0 ]; then
    USER="$1"
  fi
fi

if [ "${LOCAL_MODE}" -eq 0 ]; then
  LOCAL_IPV4="$(ip -4 -o addr show scope global | awk '{print $4}' | cut -d'/' -f1 | head -n1 || true)"
  if [ -n "${LOCAL_IPV4}" ] && [ "${BOARD}" = "${LOCAL_IPV4}" ]; then
    echo "ERROR: target ${BOARD} matches this host's local IPv4 (${LOCAL_IPV4}), likely your local machine."
    echo "Use --local for this machine, or set KV260_BOARD_IP to the board address."
    exit 1
  fi
fi

SSH_OPTS=""
if ssh -V 2>&1 | grep -qiE 'OpenSSH|openssh'; then
  SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
fi

run_xrdp_checks() {
  if ! command -v xrdp >/dev/null 2>&1; then
    echo "ERROR: xrdp package not installed in target rootfs."
    if command -v dnf >/dev/null 2>&1; then
      echo "Try: dnf list xrdp xorgxrdp (package not present in this feed if it fails)."
    fi
    return 1
  fi

  if [ ! -f /etc/xrdp/startwm.sh ] || ! grep -q "Xsession" /etc/xrdp/startwm.sh; then
    echo "WARN: /etc/xrdp/startwm.sh missing or does not reference Xsession."
    if [ "${REPAIR_STARTWM}" = "1" ]; then
      mkdir -p /etc/xrdp
      cat > /etc/xrdp/startwm.sh <<'EOF'
#!/bin/sh
export XDG_SESSION_TYPE=x11
exec /etc/X11/Xsession
EOF
      chmod 755 /etc/xrdp/startwm.sh
      echo "Created /etc/xrdp/startwm.sh with Xsession fallback."
    else
      echo "Use --repair-startwm to create a default startwm.sh."
    fi
  fi

  if [ ! -f /etc/xrdp/xrdp.ini ]; then
    echo "ERROR: /etc/xrdp/xrdp.ini missing"
    return 1
  fi
  if ! grep -Eq "^\\[Xorg\\]" /etc/xrdp/xrdp.ini || ! grep -q "code=20" /etc/xrdp/xrdp.ini; then
    echo "WARN: xrdp.ini does not contain an Xorg session with code=20"
  fi

  if [ ! -f /etc/xrdp/sesman.ini ]; then
    echo "WARN: /etc/xrdp/sesman.ini missing"
  fi

  if command -v ss >/dev/null 2>&1; then
    echo "Checking listener on 3389:"
    ss -ltnp | grep -E ":3389\\b" || true
  elif command -v netstat >/dev/null 2>&1; then
    echo "Checking listener on 3389:"
    netstat -ltnp 2>/dev/null | grep -E ":3389\\b" || true
  fi

  if [ "${SKIP_SERVICE_RESTART}" = "1" ]; then
    return 0
  fi

  if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemd not available on target"
    return 1
  fi

  PRIV=""
  if [ "$(id -u)" -ne 0 ]; then
    PRIV="sudo "
  fi
  ${PRIV}systemctl enable --now xrdp
  ${PRIV}systemctl enable --now xrdp-sesman
  ${PRIV}systemctl restart xrdp || true
  ${PRIV}systemctl restart xrdp-sesman || true
  echo "--- xrdp status ---"
  ${PRIV}systemctl status --no-pager -l xrdp xrdp-sesman
}

if [ "${LOCAL_MODE}" -eq 1 ]; then
  run_xrdp_checks
else
  if ! command -v ssh >/dev/null 2>&1; then
    echo "ssh not found on host"
    exit 1
  fi
  echo "Connecting to ${USER}@${BOARD} ..."
  ssh ${SSH_OPTS} \
    "${USER}@${BOARD}" \
    "REPAIR_STARTWM=${REPAIR_STARTWM} SKIP_SERVICE_RESTART=${SKIP_SERVICE_RESTART} sh -eu -s" <<'EOS'
if ! command -v xrdp >/dev/null 2>&1; then
  echo "ERROR: xrdp package not installed in target rootfs."
  if command -v dnf >/dev/null 2>&1; then
    echo "Try: dnf list xrdp xorgxrdp (package not present in this feed if it fails)."
  fi
  exit 1
fi

if [ ! -f /etc/xrdp/startwm.sh ] || ! grep -q "Xsession" /etc/xrdp/startwm.sh; then
  echo "WARN: /etc/xrdp/startwm.sh missing or does not reference Xsession."
  if [ "${REPAIR_STARTWM}" = "1" ]; then
    mkdir -p /etc/xrdp
    cat > /etc/xrdp/startwm.sh <<'STARTWM'
#!/bin/sh
export XDG_SESSION_TYPE=x11
exec /etc/X11/Xsession
STARTWM
    chmod 755 /etc/xrdp/startwm.sh
    echo "Created /etc/xrdp/startwm.sh with Xsession fallback."
  else
    echo "Use --repair-startwm to create a default startwm.sh."
  fi
fi

if [ ! -f /etc/xrdp/xrdp.ini ]; then
  echo "ERROR: /etc/xrdp/xrdp.ini missing"
  exit 1
fi
if ! grep -Eq "^\\[Xorg\\]" /etc/xrdp/xrdp.ini || ! grep -q "code=20" /etc/xrdp/xrdp.ini; then
  echo "WARN: xrdp.ini does not contain an Xorg session with code=20"
fi

if [ ! -f /etc/xrdp/sesman.ini ]; then
  echo "WARN: /etc/xrdp/sesman.ini missing"
fi

if command -v ss >/dev/null 2>&1; then
  echo "Checking listener on 3389:"
  ss -ltnp | grep -E ":3389\\b" || true
elif command -v netstat >/dev/null 2>&1; then
  echo "Checking listener on 3389:"
  netstat -ltnp 2>/dev/null | grep -E ":3389\\b" || true
fi

if [ "${SKIP_SERVICE_RESTART}" = "1" ]; then
  exit 0
fi

if ! command -v systemctl >/dev/null 2>&1; then
  echo "systemd not available on target"
  exit 1
fi

PRIV=""
if [ "$(id -u)" -ne 0 ]; then
  PRIV="sudo "
fi
${PRIV}systemctl enable --now xrdp
${PRIV}systemctl enable --now xrdp-sesman
${PRIV}systemctl restart xrdp || true
${PRIV}systemctl restart xrdp-sesman || true
echo "--- xrdp status ---"
${PRIV}systemctl status --no-pager -l xrdp xrdp-sesman
EOS
fi

if [ "${LOCAL_MODE}" -eq 1 ]; then
  echo "Done. Test locally with your RDP client:"
  echo "  mstsc /v:<target-ip>:3389"
else
  echo "Done on target ${BOARD}. Then test from your RDP client host with:"
  echo "  mstsc /v:${BOARD}:3389"
fi
