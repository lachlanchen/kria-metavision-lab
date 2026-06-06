#!/usr/bin/env sh
set -eu

PROJECT_DIR="${KV260_PROJECT_DIR:-/home/petalinux/Projects/kria-kv260-starter}"
WINDOWS_HOST="${KV260_WINDOWS_HOST:-192.168.1.166}"
WINDOWS_USER="${KV260_WINDOWS_USER:-Administrator}"
WINDOWS_KEY="${KV260_WINDOWS_KEY:-/home/petalinux/.ssh/id_dropbear_rsa}"
CACHE_DIR="${KV260_CODEX_SESSION_CACHE:-${PROJECT_DIR}/private/windows-codex-history}"

SESSION_ID=""
REMOTE_PATH=""
LIST_ONLY=0

usage() {
  cat <<'USAGE'
Usage:
  fetch-windows-codex-session.sh --session-id SESSION_ID
  fetch-windows-codex-session.sh --remote-path C:/Users/Administrator/.codex/sessions/.../file.jsonl
  fetch-windows-codex-session.sh --list

Environment:
  KV260_WINDOWS_HOST          default: 192.168.1.166
  KV260_WINDOWS_USER          default: Administrator
  KV260_WINDOWS_KEY           default: /home/petalinux/.ssh/id_dropbear_rsa
  KV260_PROJECT_DIR           default: /home/petalinux/Projects/kria-kv260-starter
  KV260_CODEX_SESSION_CACHE   default: $KV260_PROJECT_DIR/private/windows-codex-history

Raw JSONL is private. Keep it in private/windows-codex-history only.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --session-id)
      SESSION_ID="${2:-}"
      shift 2
      ;;
    --remote-path)
      REMOTE_PATH="${2:-}"
      shift 2
      ;;
    --list)
      LIST_ONLY=1
      shift
      ;;
    --cache-dir)
      CACHE_DIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ ! -f "${WINDOWS_KEY}" ]; then
  echo "missing Windows SSH key: ${WINDOWS_KEY}" >&2
  exit 1
fi

if [ "${LIST_ONLY}" -eq 1 ]; then
  ssh -i "${WINDOWS_KEY}" -y "${WINDOWS_USER}@${WINDOWS_HOST}" \
    'cmd /c dir /s /b C:\Users\Administrator\.codex\sessions\*.jsonl'
  exit 0
fi

if [ -z "${REMOTE_PATH}" ]; then
  if [ -z "${SESSION_ID}" ]; then
    echo "provide --session-id or --remote-path" >&2
    usage >&2
    exit 2
  fi

  FOUND="$(ssh -i "${WINDOWS_KEY}" -y "${WINDOWS_USER}@${WINDOWS_HOST}" \
    "cmd /c findstr /s /m /c:\"${SESSION_ID}\" C:\\Users\\Administrator\\.codex\\sessions\\*.jsonl" \
    | tr -d '\r' | sed -n '1p')"

  if [ -z "${FOUND}" ]; then
    echo "no Windows Codex session found for id: ${SESSION_ID}" >&2
    exit 1
  fi

  REMOTE_PATH="$(printf '%s' "${FOUND}" | sed 's#\\#/#g')"
fi

REMOTE_PATH="$(printf '%s' "${REMOTE_PATH}" | sed 's#\\#/#g')"
BASENAME="$(basename "${REMOTE_PATH}")"

mkdir -p "${CACHE_DIR}"
DEST="${CACHE_DIR}/${BASENAME}"

scp -i "${WINDOWS_KEY}" "${WINDOWS_USER}@${WINDOWS_HOST}:${REMOTE_PATH}" "${DEST}"
chmod 600 "${DEST}"

if [ ! -f "${CACHE_DIR}/README.md" ]; then
  cat > "${CACHE_DIR}/README.md" <<'README'
# Private Windows Codex History Mirror

This folder is intentionally ignored by Git.

Purpose:

- inspect Windows-side Codex conversation context when needed;
- understand recent Windows Arduino / DualLampHI / V-SPICE work before controlling hardware;
- avoid repeatedly SSH-reading the full Windows history.

Rules:

- do not commit this folder;
- do not paste the full history into tracked docs;
- summarize only relevant, non-sensitive operational facts into `references/`, `docs/`, `AGENTS.md`, or skills;
- prefer curated handoff docs and skills for canonical state.
README
  chmod 600 "${CACHE_DIR}/README.md"
fi

{
  printf 'source=%s@%s:%s\n' "${WINDOWS_USER}" "${WINDOWS_HOST}" "${REMOTE_PATH}"
  printf 'local=%s\n' "${DEST}"
  printf 'fetched_at_utc='
  date -u '+%Y-%m-%dT%H:%M:%SZ'
} > "${CACHE_DIR}/source_metadata.txt"
chmod 600 "${CACHE_DIR}/source_metadata.txt"

printf 'Fetched Windows Codex session to:\n%s\n' "${DEST}"
printf 'Metadata:\n%s\n' "${CACHE_DIR}/source_metadata.txt"
