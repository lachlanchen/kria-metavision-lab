#!/usr/bin/env python3
"""Windows/client-side helper for KV260 event recording experiments.

Typical use: control an Arduino-connected illuminator on Windows, ask the
KV260 HTTP API to record raw PSE2 events, then download the raw file and JSON
sidecar back to the Windows machine.
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


DEFAULT_BOARD_URL = os.environ.get("KV260_EVENT_API_URL", "http://192.168.1.100:8765")


def parse_metadata(items):
    result = {}
    for item in items or []:
        if "=" not in item:
            raise ValueError("metadata must be key=value: %s" % item)
        key, value = item.split("=", 1)
        result[key.strip()] = value.strip()
    return result


class KV260ApiClient:
    def __init__(self, base_url, token=""):
        self.base_url = base_url.rstrip("/")
        self.token = token

    def request_json(self, method, path, body=None):
        url = self.base_url + path
        data = None
        headers = {"Content-Type": "application/json"}
        if self.token:
            headers["Authorization"] = "Bearer %s" % self.token
        if body is not None:
            data = json.dumps(body).encode("utf-8")
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            details = exc.read().decode("utf-8", "replace")
            raise RuntimeError("HTTP %s %s: %s" % (exc.code, path, details))

    def status(self):
        return self.request_json("GET", "/api/v1/status")

    def start(self, body):
        return self.request_json("POST", "/api/v1/record/start", body)

    def stop(self, close_stream=True):
        return self.request_json("POST", "/api/v1/record/stop", {"close_stream": close_stream})

    def list_recordings(self, limit=20):
        return self.request_json("GET", "/api/v1/recordings?limit=%s" % int(limit))

    def download(self, remote_path, output_dir, kind="raw"):
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)
        query = urllib.parse.urlencode({"path": remote_path, "kind": kind})
        url = self.base_url + "/api/v1/recordings/download?" + query
        headers = {}
        if self.token:
            headers["Authorization"] = "Bearer %s" % self.token
        request = urllib.request.Request(url, headers=headers, method="GET")
        local_path = output_dir / Path(remote_path).name
        if kind == "json" and not str(local_path).endswith(".json"):
            local_path = Path(str(local_path) + ".json")
        with urllib.request.urlopen(request, timeout=120) as response, open(local_path, "wb") as file_obj:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                file_obj.write(chunk)
        return str(local_path)


def open_arduino(port, baud, timeout):
    try:
        import serial
    except ImportError as exc:
        raise RuntimeError("pyserial is required for Arduino control. Install with: python -m pip install pyserial") from exc
    return serial.Serial(port=port, baudrate=baud, timeout=timeout, write_timeout=timeout)


def send_arduino(arduino, command, newline=True, delay=0.0):
    if not command:
        return
    text = str(command)
    if newline and not text.endswith("\n"):
        text += "\n"
    arduino.write(text.encode("utf-8"))
    arduino.flush()
    if delay > 0:
        time.sleep(delay)


def build_start_body(args):
    metadata = parse_metadata(args.metadata)
    metadata.update(
        {
            "client": "KV260EventExperimentClient.py",
            "light_mode": getattr(args, "light_mode", ""),
            "arduino_port": getattr(args, "arduino_port", "") or "",
            "arduino_baud": getattr(args, "arduino_baud", 0) or 0,
        }
    )
    return {
        "prefix": args.prefix,
        "filename": args.filename,
        "folder": args.folder,
        "device": args.device,
        "takeover": not args.no_takeover,
        "force_takeover": args.force_takeover,
        "count_events": args.count_events,
        "metadata": metadata,
    }


def print_json(data):
    print(json.dumps(data, indent=2, sort_keys=True))


def command_status(api, args):
    print_json(api.status())


def command_start(api, args):
    print_json(api.start(build_start_body(args)))


def command_stop(api, args):
    result = api.stop(close_stream=not args.keep_stream)
    print_json(result)


def command_list(api, args):
    print_json(api.list_recordings(limit=args.limit))


def command_download(api, args):
    raw = api.download(args.path, args.output_dir, kind=args.kind)
    print(raw)


def command_run(api, args):
    arduino = None
    downloaded = []
    recording_started = False
    recording_stopped = False
    light_on_sent = False
    light_off_sent = False
    try:
        if args.arduino_port:
            arduino = open_arduino(args.arduino_port, args.arduino_baud, args.arduino_timeout)
            time.sleep(args.arduino_ready_delay)

        start_body = build_start_body(args)
        if args.light_mode == "record-then-light":
            start_result = api.start(start_body)
            recording_started = True
            print("recording_started", start_result.get("current_recording", {}).get("path", ""))
            time.sleep(args.pre_trigger_seconds)
            if arduino and args.light_on:
                send_arduino(arduino, args.light_on, newline=not args.no_newline, delay=args.after_light_seconds)
                light_on_sent = True
            time.sleep(args.seconds)
        else:
            if arduino and args.light_on:
                send_arduino(arduino, args.light_on, newline=not args.no_newline, delay=args.after_light_seconds)
                light_on_sent = True
            time.sleep(args.settle_seconds)
            start_result = api.start(start_body)
            recording_started = True
            print("recording_started", start_result.get("current_recording", {}).get("path", ""))
            time.sleep(args.seconds)

        stop_result = api.stop(close_stream=True)
        recording_stopped = True
        stopped = stop_result.get("stopped_recording") or {}
        raw_path = stopped.get("path") or ""
        meta_path = stopped.get("meta_path") or (raw_path + ".json" if raw_path else "")
        print("recording_stopped", raw_path)

        if arduino and args.light_off:
            send_arduino(arduino, args.light_off, newline=not args.no_newline, delay=args.after_light_seconds)
            light_off_sent = True

        if raw_path and not args.no_download:
            downloaded.append(api.download(raw_path, args.output_dir, kind="raw"))
            if meta_path:
                downloaded.append(api.download(meta_path, args.output_dir, kind="raw"))

        print_json({"ok": True, "raw_path": raw_path, "meta_path": meta_path, "downloaded": downloaded, "stop": stop_result})
    finally:
        if recording_started and not recording_stopped:
            try:
                api.stop(close_stream=True)
            except Exception as exc:
                print("warning: could not stop KV260 recording after failure: %s" % exc, file=sys.stderr)
        if arduino and light_on_sent and not light_off_sent and args.light_off:
            try:
                send_arduino(arduino, args.light_off, newline=not args.no_newline, delay=args.after_light_seconds)
            except Exception as exc:
                print("warning: could not send Arduino light-off command after failure: %s" % exc, file=sys.stderr)
        if arduino:
            arduino.close()


def add_start_options(parser):
    parser.add_argument("--prefix", default="experiment")
    parser.add_argument("--filename", default="")
    parser.add_argument("--folder", default="")
    parser.add_argument("--device", default="/dev/video0")
    parser.add_argument("--metadata", action="append", default=[], help="extra metadata key=value")
    parser.add_argument("--no-takeover", action="store_true", help="do not stop existing GUI/native viewers first")
    parser.add_argument("--force-takeover", action="store_true", help="TERM/KILL remaining /dev/video0 owners if graceful takeover fails")
    parser.add_argument("--count-events", action="store_true", help="decode event counts during recording; costs CPU")


def parse_args(argv):
    parser = argparse.ArgumentParser(description="KV260 event recording API client with optional Arduino trigger control")
    parser.add_argument("--board-url", default=DEFAULT_BOARD_URL)
    parser.add_argument("--token", default=os.environ.get("KV260_EVENT_API_TOKEN", ""))
    sub = parser.add_subparsers(dest="command", required=True)

    status = sub.add_parser("status")
    status.set_defaults(func=command_status)

    start = sub.add_parser("start")
    add_start_options(start)
    start.set_defaults(func=command_start)

    stop = sub.add_parser("stop")
    stop.add_argument("--keep-stream", action="store_true")
    stop.set_defaults(func=command_stop)

    list_cmd = sub.add_parser("list")
    list_cmd.add_argument("--limit", type=int, default=20)
    list_cmd.set_defaults(func=command_list)

    download = sub.add_parser("download")
    download.add_argument("--path", required=True)
    download.add_argument("--kind", choices=("raw", "json"), default="raw")
    download.add_argument("--output-dir", default=str(Path.cwd()))
    download.set_defaults(func=command_download)

    run = sub.add_parser("run")
    add_start_options(run)
    run.add_argument("--seconds", type=float, default=2.0)
    run.add_argument("--light-mode", choices=("record-then-light", "light-then-record"), default="record-then-light")
    run.add_argument("--pre-trigger-seconds", type=float, default=0.1)
    run.add_argument("--settle-seconds", type=float, default=0.1)
    run.add_argument("--arduino-port", default="")
    run.add_argument("--arduino-baud", type=int, default=115200)
    run.add_argument("--arduino-timeout", type=float, default=2.0)
    run.add_argument("--arduino-ready-delay", type=float, default=2.0)
    run.add_argument("--light-on", default="")
    run.add_argument("--light-off", default="")
    run.add_argument("--after-light-seconds", type=float, default=0.05)
    run.add_argument("--no-newline", action="store_true")
    run.add_argument("--output-dir", default=str(Path.cwd() / "kv260-event-recordings"))
    run.add_argument("--no-download", action="store_true")
    run.set_defaults(func=command_run)

    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv or sys.argv[1:])
    api = KV260ApiClient(args.board_url, token=args.token)
    args.func(api, args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
