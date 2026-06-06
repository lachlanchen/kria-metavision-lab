#!/usr/bin/env sh
set -eu

PROJECT_DIR="${KV260_PROJECT_DIR:-/home/petalinux/Projects/kria-kv260-starter}"
BASE_URL="${KV260_EVENT_API_URL:-http://127.0.0.1:8765}"
SECONDS="2"
PREFIX="skill_recording"
METADATA_SOURCE="kv260-windows-arduino-skill"

usage() {
  cat <<'EOF'
Usage:
  kv260-record-once.sh [--seconds N] [--prefix NAME] [--url URL]

Starts the KV260 recording API if needed, records for N seconds, stops, and
prints the API result JSON. It records with takeover=true and count_events=false.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --seconds)
      SECONDS="$2"
      shift 2
      ;;
    --prefix)
      PREFIX="$2"
      shift 2
      ;;
    --url)
      BASE_URL="$2"
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

cd "${PROJECT_DIR}"
./scripts/kv260-event-camera-api.sh start >/dev/null

python3 - "${BASE_URL}" "${SECONDS}" "${PREFIX}" "${METADATA_SOURCE}" <<'PY'
import json
import sys
import time
import urllib.request

base_url, seconds, prefix, source = sys.argv[1], float(sys.argv[2]), sys.argv[3], sys.argv[4]

def post(path, body):
    data = json.dumps(body).encode("utf-8")
    request = urllib.request.Request(
        base_url.rstrip("/") + path,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))

start = post(
    "/api/v1/record/start",
    {
        "prefix": prefix,
        "takeover": True,
        "force_takeover": False,
        "count_events": False,
        "metadata": {"source": source},
    },
)
print(json.dumps({"started": start.get("current_recording")}, indent=2, sort_keys=True))
time.sleep(seconds)
stop = post("/api/v1/record/stop", {"close_stream": True})
print(json.dumps(stop, indent=2, sort_keys=True))
PY
