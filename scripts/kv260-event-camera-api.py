#!/usr/bin/env python3
"""Headless HTTP API for KV260 Prophesee event-camera recording.

The API intentionally reuses the same V4L2 raw writer as the GUI, but runs
without GTK preview work. Windows-side experiment scripts can control Arduino
illumination locally, then call this API to start/stop recording and download
the captured PSE2/EVT2.1 payload plus JSON sidecar.
"""

import argparse
import importlib.util
import json
import os
import signal
import subprocess
import sys
import threading
import time
import urllib.parse
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(HERE)
APP_PATH = os.path.join(HERE, "kv260-event-camera-app.py")
SWITCHER = os.path.join(HERE, "kv260-event-camera-switch.sh")
DEFAULT_HOST = os.environ.get("KV260_EVENT_API_HOST", "0.0.0.0")
DEFAULT_PORT = int(os.environ.get("KV260_EVENT_API_PORT", "8765"))
DEFAULT_RECORD_DIR = os.path.abspath(
    os.path.expanduser(os.environ.get("KV260_EVENT_API_RECORD_DIR", "~/event_recordings"))
)
DEFAULT_DEVICE = os.environ.get("KV260_EVENT_API_DEVICE", "/dev/video0")
DEFAULT_TOKEN = os.environ.get("KV260_EVENT_API_TOKEN", "")
MAX_JSON_BYTES = 1024 * 1024


def load_camera_module():
    spec = importlib.util.spec_from_file_location("kv260_event_camera_app", APP_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


camera_app = load_camera_module()


class NullRenderer:
    def snapshot_settings(self):
        return {
            "accumulation_us": 10000,
            "fps": 0,
            "palette": "headless",
            "polarity": "All",
            "point_radius": 0,
            "trail": 0,
            "show_osd": False,
            "preview_enabled": False,
        }


def now_iso():
    return datetime.now().isoformat(timespec="seconds")


def clean_name(value, fallback):
    text = str(value or "").strip()
    if not text:
        text = fallback
    keep = []
    for char in text:
        if char.isalnum() or char in ("-", "_", ".", "+"):
            keep.append(char)
        elif char in (" ", ":"):
            keep.append("_")
    cleaned = "".join(keep).strip("._")
    return cleaned or fallback


def path_inside(path, root):
    path = os.path.abspath(os.path.expanduser(path))
    root = os.path.abspath(os.path.expanduser(root))
    return path == root or path.startswith(root + os.sep)


def file_size(path):
    try:
        return os.path.getsize(path)
    except OSError:
        return 0


class RecordingController:
    def __init__(self, record_dir, default_device):
        self.record_dir = os.path.abspath(os.path.expanduser(record_dir))
        self.default_device = default_device
        self.lock = threading.RLock()
        self.stream = None
        self.device = default_device
        self.status_lines = []
        self.last_status = "idle"
        self.current_recording = None
        self.last_result = None
        os.makedirs(self.record_dir, exist_ok=True)

    def note_status(self, text):
        text = str(text)
        with self.lock:
            self.last_status = text
            self.status_lines.append({"time": now_iso(), "text": text})
            self.status_lines = self.status_lines[-80:]
        print("[%s] %s" % (now_iso(), text), flush=True)

    def make_path(self, body):
        folder = body.get("folder") or self.record_dir
        if not os.path.isabs(str(folder)):
            folder = os.path.join(self.record_dir, str(folder))
        folder = os.path.abspath(os.path.expanduser(str(folder)))
        if not path_inside(folder, self.record_dir):
            raise ValueError("folder must be inside %s" % self.record_dir)

        filename = body.get("filename")
        if filename:
            filename = clean_name(os.path.basename(str(filename)), "event.pse2.raw")
        else:
            prefix = clean_name(body.get("prefix"), "event")
            filename = "%s_%s.pse2.raw" % (prefix, datetime.now().strftime("%Y%m%d_%H%M%S"))
        if not filename.endswith(".raw"):
            filename += ".raw"
        return os.path.join(folder, filename)

    def stop_gui_owners(self):
        if os.path.exists(SWITCHER):
            subprocess.run(
                [SWITCHER, "--stop-all"],
                cwd=PROJECT_DIR,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=12,
                check=False,
            )

    def video_owners(self, device):
        try:
            result = subprocess.run(
                ["fuser", device],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=4,
                check=False,
            )
        except Exception:
            return []
        owners = []
        for item in result.stdout.split():
            try:
                owners.append(int(item))
            except ValueError:
                pass
        return owners

    def ensure_camera_available(self, device, takeover=False, force_takeover=False):
        if takeover:
            self.stop_gui_owners()
            time.sleep(0.2)
        owners = self.video_owners(device)
        if owners and force_takeover:
            for pid in owners:
                try:
                    os.kill(pid, signal.SIGTERM)
                except OSError:
                    pass
            time.sleep(0.8)
            owners = self.video_owners(device)
            for pid in owners:
                try:
                    os.kill(pid, signal.SIGKILL)
                except OSError:
                    pass
            time.sleep(0.2)
            owners = self.video_owners(device)
        if owners:
            raise RuntimeError("%s is already owned by process(es): %s" % (device, owners))

    def start_stream_locked(self, device, count_events=False):
        if self.stream:
            return
        renderer = NullRenderer()
        self.stream = camera_app.V4L2EventStream(
            device,
            renderer,
            lambda _frame: None,
            self.note_status,
            preview_enabled=False,
            count_events=count_events,
        )
        self.stream.set_recording_priority(True)
        self.stream.start()
        deadline = time.monotonic() + 4.0
        while time.monotonic() < deadline:
            if self.stream.total_buffers > 0 or "Live camera open" in self.last_status:
                return
            if "Camera stream failed" in self.last_status or (
                self.stream.thread is not None and not self.stream.thread.is_alive()
            ):
                break
            time.sleep(0.05)
        if self.stream.thread is not None and not self.stream.thread.is_alive():
            message = self.last_status
            self.stream.stop()
            self.stream = None
            raise RuntimeError(message)

    def start_recording(self, body):
        body = body or {}
        with self.lock:
            if self.stream and self.stream.is_recording():
                raise ConflictError("recording is already active")

            device = str(body.get("device") or self.default_device)
            takeover = bool(body.get("takeover", True))
            force_takeover = bool(body.get("force_takeover", False))
            count_events = bool(body.get("count_events", False))
            output_path = self.make_path(body)
            self.ensure_camera_available(device, takeover=takeover, force_takeover=force_takeover)
            self.device = device
            self.start_stream_locked(device, count_events=count_events)

            metadata = {
                "trigger_source": "kv260-event-camera-api",
                "api_started": now_iso(),
                "api_preview_enabled": False,
                "api_count_events": count_events,
                "api_takeover": takeover,
            }
            request_metadata = body.get("metadata")
            if isinstance(request_metadata, dict):
                metadata["experiment_metadata"] = request_metadata
            self.stream.start_recording(output_path, extra_metadata=metadata)
            self.current_recording = {
                "path": output_path,
                "meta_path": output_path + ".json",
                "started": now_iso(),
                "device": device,
                "count_events": count_events,
            }
            return self.snapshot()

    def stop_recording(self, body):
        body = body or {}
        with self.lock:
            result = None
            closed_stream_stats = None
            if self.stream:
                result = self.stream.stop_recording()
                closed_stream_stats = self.stream_stats_locked(self.stream)
            if result:
                self.last_result = result
            close_stream = bool(body.get("close_stream", True))
            if close_stream and self.stream:
                self.stream.stop()
                self.stream = None
            self.current_recording = None
            response = self.snapshot()
            response["stopped_recording"] = result or self.last_result
            response["closed_stream_stats"] = closed_stream_stats
            return response

    def close(self):
        with self.lock:
            if self.stream:
                self.stream.stop()
                self.stream = None
            self.current_recording = None

    def snapshot(self):
        with self.lock:
            stream = self.stream
            recording_stats = stream.recording_snapshot() if stream and stream.is_recording() else None
            return {
                "ok": True,
                "time": now_iso(),
                "record_dir": self.record_dir,
                "device": self.device,
                "stream_running": bool(stream),
                "recording": bool(stream and stream.is_recording()),
                "current_recording": self.current_recording,
                "last_recording": self.last_result,
                "recording_stats": recording_stats,
                "stream_stats": self.stream_stats_locked(stream),
                "last_status": self.last_status,
                "status_tail": list(self.status_lines[-20:]),
            }

    def stream_stats_locked(self, stream):
        return {
            "total_buffers": stream.total_buffers if stream else 0,
            "total_events": stream.total_events if stream else 0,
            "rate_mev_s": stream.rate_mev_s if stream else 0.0,
            "preview_enabled": stream.preview_enabled if stream else False,
            "count_events": stream.count_events_enabled if stream else False,
        }

    def list_recordings(self, limit=100):
        rows = []
        with self.lock:
            root = self.record_dir
            for current_root, _dirs, files in os.walk(root):
                for name in files:
                    if not name.endswith(".raw"):
                        continue
                    path = os.path.join(current_root, name)
                    rel = os.path.relpath(path, root)
                    rows.append(
                        {
                            "name": name,
                            "relative_path": rel,
                            "path": path,
                            "meta_path": path + ".json",
                            "size": file_size(path),
                            "meta_size": file_size(path + ".json"),
                            "mtime": os.path.getmtime(path),
                        }
                    )
            rows.sort(key=lambda item: item["mtime"], reverse=True)
            return {"ok": True, "record_dir": root, "recordings": rows[: max(1, int(limit))]}

    def resolve_download_path(self, requested, kind="raw"):
        if not requested:
            raise ValueError("missing path")
        if os.path.isabs(requested):
            path = os.path.abspath(os.path.expanduser(requested))
        else:
            path = os.path.abspath(os.path.join(self.record_dir, requested))
        if kind == "json" and not path.endswith(".json"):
            path += ".json"
        if not path_inside(path, self.record_dir):
            raise ValueError("download path must be inside %s" % self.record_dir)
        if not os.path.exists(path):
            raise FileNotFoundError(path)
        return path


class ConflictError(Exception):
    pass


class ApiHandler(BaseHTTPRequestHandler):
    server_version = "KV260EventAPI/1.0"

    def log_message(self, fmt, *args):
        print("[%s] %s" % (now_iso(), fmt % args), flush=True)

    @property
    def controller(self):
        return self.server.controller

    @property
    def token(self):
        return self.server.token

    def check_auth(self):
        if not self.token:
            return True
        auth = self.headers.get("Authorization", "")
        header_token = self.headers.get("X-KV260-Token", "")
        if auth == "Bearer %s" % self.token or header_token == self.token:
            return True
        self.send_json({"ok": False, "error": "unauthorized"}, status=401)
        return False

    def send_json(self, payload, status=200):
        encoded = json.dumps(payload, indent=2, sort_keys=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, X-KV260-Token, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()
        self.wfile.write(encoded)

    def read_json(self):
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0:
            return {}
        if length > MAX_JSON_BYTES:
            raise ValueError("request body too large")
        data = self.rfile.read(length)
        return json.loads(data.decode("utf-8"))

    def do_OPTIONS(self):
        self.send_json({"ok": True})

    def do_GET(self):
        if not self.check_auth():
            return
        parsed = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(parsed.query)
        try:
            if parsed.path in ("/", "/api/v1/help"):
                self.send_json(self.help_payload())
            elif parsed.path in ("/api/v1/health", "/api/v1/status"):
                self.send_json(self.controller.snapshot())
            elif parsed.path == "/api/v1/recordings":
                limit = int(query.get("limit", ["100"])[0])
                self.send_json(self.controller.list_recordings(limit=limit))
            elif parsed.path == "/api/v1/recordings/download":
                requested = query.get("path", query.get("name", [""]))[0]
                kind = query.get("kind", ["raw"])[0]
                self.send_file(self.controller.resolve_download_path(requested, kind=kind))
            else:
                self.send_json({"ok": False, "error": "not found", "path": parsed.path}, status=404)
        except Exception as exc:
            self.send_json({"ok": False, "error": str(exc)}, status=500)

    def do_POST(self):
        if not self.check_auth():
            return
        parsed = urllib.parse.urlparse(self.path)
        try:
            body = self.read_json()
            if parsed.path == "/api/v1/record/start":
                self.send_json(self.controller.start_recording(body))
            elif parsed.path == "/api/v1/record/stop":
                self.send_json(self.controller.stop_recording(body))
            elif parsed.path == "/api/v1/record/recover":
                self.controller.stop_gui_owners()
                self.send_json(self.controller.snapshot())
            else:
                self.send_json({"ok": False, "error": "not found", "path": parsed.path}, status=404)
        except ConflictError as exc:
            self.send_json({"ok": False, "error": str(exc)}, status=409)
        except Exception as exc:
            self.send_json({"ok": False, "error": str(exc)}, status=500)

    def send_file(self, path):
        size = os.path.getsize(path)
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(size))
        self.send_header("Content-Disposition", 'attachment; filename="%s"' % os.path.basename(path))
        self.end_headers()
        with open(path, "rb") as file_obj:
            while True:
                chunk = file_obj.read(1024 * 1024)
                if not chunk:
                    break
                self.wfile.write(chunk)

    def help_payload(self):
        return {
            "ok": True,
            "name": "KV260 Event Camera API",
            "endpoints": {
                "GET /api/v1/status": "Current stream and recording status.",
                "POST /api/v1/record/start": "Start a headless raw PSE2 recording.",
                "POST /api/v1/record/stop": "Stop recording and flush the writer.",
                "GET /api/v1/recordings": "List recent recordings.",
                "GET /api/v1/recordings/download?path=<relative-or-absolute-path>": "Download a raw or JSON recording file.",
            },
            "start_body": {
                "prefix": "experiment",
                "filename": "optional_name.pse2.raw",
                "folder": "optional relative folder under record_dir",
                "device": DEFAULT_DEVICE,
                "takeover": True,
                "force_takeover": False,
                "count_events": False,
                "metadata": {"light": "on"},
            },
        }


def parse_args(argv):
    parser = argparse.ArgumentParser(description="KV260 headless event recording HTTP API")
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--port", default=DEFAULT_PORT, type=int)
    parser.add_argument("--record-dir", default=DEFAULT_RECORD_DIR)
    parser.add_argument("--device", default=DEFAULT_DEVICE)
    parser.add_argument("--token", default=DEFAULT_TOKEN)
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv or sys.argv[1:])
    controller = RecordingController(args.record_dir, args.device)
    server = ThreadingHTTPServer((args.host, args.port), ApiHandler)
    server.controller = controller
    server.token = args.token

    def stop_server(_signum, _frame):
        controller.close()
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop_server)
    signal.signal(signal.SIGINT, stop_server)
    print(
        "[%s] KV260 Event Camera API listening on http://%s:%s record_dir=%s auth=%s"
        % (now_iso(), args.host, args.port, controller.record_dir, "on" if args.token else "off"),
        flush=True,
    )
    try:
        server.serve_forever()
    finally:
        controller.close()
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
