#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${WORKSPACE_DIR}/.env"
OUT_DIR="${WORKSPACE_DIR}/references"

usage() {
  cat <<'EOF'
Usage:
  prophesee-support-dump.sh [options]

Options:
  --cookie-file PATH      Path to browser-exported cookie jar (for support.prophesee.ai)
  --download              Download discovered artifact links
  --download-dir DIR      Directory for downloaded artifacts (default: references/prophesee-downloads)
  --no-color              Disable ANSI color output
  --help                  Show this help message

Environment:
  .env should provide PROPHESSEE_KRIA_MAIN_ARTICLE_API and
  PROPHESSEE_KRIA_RELEASE_NOTES_API.
  Authenticated cookie is required for the protected main KB article.
EOF
}

NO_COLOR=0
COOKIE_FILE=""
DO_DOWNLOAD=0
DOWNLOAD_DIR="${WORKSPACE_DIR}/references/prophesee-downloads"

while (( "$#" )); do
  case "$1" in
    --cookie-file)
      if [[ $# -lt 2 ]]; then
        echo "error: --cookie-file requires a path" >&2
        exit 1
      fi
      COOKIE_FILE="$2"
      shift 2
      ;;
    --download)
      DO_DOWNLOAD=1
      shift
      ;;
    --download-dir)
      if [[ $# -lt 2 ]]; then
        echo "error: --download-dir requires a path" >&2
        exit 1
      fi
      DOWNLOAD_DIR="$2"
      shift 2
      ;;
    --no-color)
      NO_COLOR=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

if [[ -z "${COOKIE_FILE}" && -n "${PROPHESSEE_SUPPORT_SESSION_COOKIE_FILE:-}" ]]; then
  COOKIE_FILE="${PROPHESSEE_SUPPORT_SESSION_COOKIE_FILE}"
fi

if [[ -z "${PROPHESSEE_KRIA_MAIN_ARTICLE_API:-}" || -z "${PROPHESSEE_KRIA_RELEASE_NOTES_API:-}" ]]; then
  echo "error: required API URLs are missing from .env" >&2
  exit 1
fi

COLOR_BLUE="\033[1;34m"
COLOR_GREEN="\033[1;32m"
COLOR_RED="\033[0;31m"
COLOR_RESET="\033[0m"
if (( NO_COLOR )); then
  COLOR_BLUE=""
  COLOR_GREEN=""
  COLOR_RED=""
  COLOR_RESET=""
fi

fetch_api() {
  local url="$1"
  local out_json="$2"
  local status

  if [[ -n "${COOKIE_FILE}" && -f "${COOKIE_FILE}" ]]; then
    status="$(curl -sS -L -b "${COOKIE_FILE}" -o "${out_json}" -w '%{http_code}' "${url}")"
  else
    status="$(curl -sS -L -o "${out_json}" -w '%{http_code}' "${url}")"
  fi
  echo "${status}"
}

extract_links() {
  local json_file="$1"
  local prefix="$2"
  python3 - "$json_file" "$prefix" <<'PY'
import json
import re
import sys

path, prefix = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8", errors="ignore") as f:
    text = f.read().strip()

if not text:
    print(f"{prefix} no payload")
    sys.exit(0)

if "FORBIDDEN" in text and "errorCode" in text:
    print(f"{prefix} access denied (FORBIDDEN)")
    sys.exit(0)

try:
    data = json.loads(text)
except json.JSONDecodeError:
    print(f"{prefix} non-json payload")
    print(text[:240])
    sys.exit(0)

title = data.get("title", "(no title)")
web_url = data.get("webUrl", "(no webUrl)")
print(f"{prefix} title: {title}")
print(f"{prefix} webUrl: {web_url}")

answer = data.get("answer", "") or ""
links = sorted(set(re.findall(r'href=\"([^\"]+)\"', answer)))
if links:
    print(f"{prefix} links in answer({len(links)}):")
    for link in links:
        print(f"{prefix}  - {link}")
else:
    print(f"{prefix} no links found in answer")
PY
}

collect_download_links() {
  local json_file="$1"
  python3 - "$json_file" <<'PY'
import json
import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8", errors="ignore") as f:
    text = f.read().strip()

if not text or ("FORBIDDEN" in text and "errorCode" in text):
    sys.exit(0)

try:
    data = json.loads(text)
except Exception:
    sys.exit(0)

answer = data.get("answer", "") or ""
links = re.findall(r'href=\"([^\"]+)\"', answer)

for link in sorted(set(links)):
    if re.search(r"\.(zip|img|bin|rpm|xz|gz|bz2|tar|deb|iso|md5|txt|pdf|wic|raw|bit)$", link, re.IGNORECASE):
        print(link)
PY
}

dump_json() {
  local label="$1"
  local url="$2"
  local out_file="$3"
  local status

  status="$(fetch_api "${url}" "${out_file}")"
  echo -e "${COLOR_BLUE}${label}${COLOR_RESET} HTTP ${status}"
  extract_links "${out_file}" "${label}"
}

mkdir -p "${OUT_DIR}"
MAIN_JSON="${OUT_DIR}/prophesee-kv260-main-api.json"
RELEASE_JSON="${OUT_DIR}/prophesee-kv260-release-notes-api.json"

echo -e "${COLOR_GREEN}Target workspace:${COLOR_RESET} ${WORKSPACE_DIR}"
if [[ -n "${COOKIE_FILE}" ]]; then
  if [[ -f "${COOKIE_FILE}" ]]; then
    echo -e "${COLOR_GREEN}Cookie file:${COLOR_RESET} ${COOKIE_FILE}"
  else
    echo -e "${COLOR_RED}Cookie file missing:${COLOR_RESET} ${COOKIE_FILE}"
    COOKIE_FILE=""
  fi
fi

echo -e "${COLOR_BLUE}Fetching protected main KB article payload...${COLOR_RESET}"
dump_json "[main]" "${PROPHESSEE_KRIA_MAIN_ARTICLE_API}" "${MAIN_JSON}"
echo
echo -e "${COLOR_BLUE}Fetching public release-notes payload...${COLOR_RESET}"
dump_json "[release-notes]" "${PROPHESSEE_KRIA_RELEASE_NOTES_API}" "${RELEASE_JSON}"
echo

if (( DO_DOWNLOAD )); then
  if [[ -z "${COOKIE_FILE}" ]]; then
    echo -e "${COLOR_RED}download mode requires --cookie-file (authenticated session not available).${COLOR_RESET}"
    exit 1
  fi

  mkdir -p "${DOWNLOAD_DIR}"
  mapfile -t artifact_urls < <(
    {
      collect_download_links "${MAIN_JSON}"
      collect_download_links "${RELEASE_JSON}"
    } | sort -u
  )

  if (( ${#artifact_urls[@]} == 0 )); then
    echo -e "${COLOR_RED}No artifact-like links found in current payloads.${COLOR_RESET}"
  else
    echo -e "${COLOR_BLUE}Downloading ${#artifact_urls[@]} artifact links to:${COLOR_RESET} ${DOWNLOAD_DIR}"
    for url in "${artifact_urls[@]}"; do
      filename="${url##*/}"
      filename="${filename%%\?*}"
      if [[ -z "${filename}" ]]; then
        filename="prophesee_artifact.bin"
      fi
      echo " - ${url}"
      curl -sS -L -b "${COOKIE_FILE}" -o "${DOWNLOAD_DIR}/${filename}" "${url}" || \
        echo -e "${COLOR_RED}  ! failed${COLOR_RESET}"
    done
  fi
fi

echo -e "${COLOR_GREEN}Output files:${COLOR_RESET}"
echo "  - ${MAIN_JSON}"
echo "  - ${RELEASE_JSON}"
echo
if (( DO_DOWNLOAD )); then
  echo "Downloaded artifacts (if any): ${DOWNLOAD_DIR}"
fi
