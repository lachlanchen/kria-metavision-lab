# KV260 Recording API Reference

Use this when starting, stopping, testing, or calling event recording.

## Files

```text
/home/petalinux/Projects/kria-kv260-starter/scripts/kv260-event-camera-api.py
/home/petalinux/Projects/kria-kv260-starter/scripts/kv260-event-camera-api.sh
/home/petalinux/Projects/kria-kv260-starter/scripts/windows/KV260EventExperimentClient.py
```

## Start / Stop

```sh
cd /home/petalinux/Projects/kria-kv260-starter
./scripts/kv260-event-camera-api.sh start
./scripts/kv260-event-camera-api.sh status
./scripts/kv260-event-camera-api.sh stop
./scripts/kv260-event-camera-api.sh tail
```

Default:

```text
URL from board:   http://127.0.0.1:8765
URL from Windows: http://192.168.1.250:8765
record dir:       /home/petalinux/event_recordings
device:           /dev/video0
auth:             off unless KV260_EVENT_API_TOKEN is set
```

## HTTP Endpoints

```text
GET  /api/v1/status
GET  /api/v1/recordings?limit=20
GET  /api/v1/recordings/download?path=<path>
POST /api/v1/record/start
POST /api/v1/record/stop
```

Start body:

```json
{
  "prefix": "illumination",
  "device": "/dev/video0",
  "takeover": true,
  "force_takeover": false,
  "count_events": false,
  "metadata": {
    "source": "windows-arduino",
    "trial": "001"
  }
}
```

Stop body:

```json
{
  "close_stream": true
}
```

## Local API Call Examples

```sh
curl http://127.0.0.1:8765/api/v1/status

curl -sS -X POST http://127.0.0.1:8765/api/v1/record/start \
  -H 'Content-Type: application/json' \
  -d '{"prefix":"test","takeover":true,"count_events":false}'

curl -sS -X POST http://127.0.0.1:8765/api/v1/record/stop \
  -H 'Content-Type: application/json' \
  -d '{"close_stream":true}'
```

## Recording Format

```text
/home/petalinux/event_recordings/*.pse2.raw
/home/petalinux/event_recordings/*.pse2.raw.json
```

The raw file is direct PSE2/EVT2.1 V4L2 payload bytes. The JSON sidecar records stats such as bytes, buffers, queue drops, and write errors.

## Ownership Rule

Only one process can own `/dev/video0`.

Check:

```sh
cd /home/petalinux/Projects/kria-kv260-starter
./scripts/kv260-event-camera-switch.sh --status
fuser /dev/video0 2>/dev/null || true
```

Stop viewers:

```sh
./scripts/kv260-event-camera-switch.sh --stop-all
```

Use `takeover=true` for remote recording starts.
