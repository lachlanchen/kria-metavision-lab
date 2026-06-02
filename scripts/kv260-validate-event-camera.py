#!/usr/bin/env python3
"""Validate the KV260 custom event camera app recording and preview paths."""

import argparse
import importlib.util
import json
import os
import pathlib
import socket
import subprocess
import sys
import time

import numpy as np


HERE = pathlib.Path(__file__).resolve().parent
PROJECT_DIR = HERE.parent
APP_PATH = HERE / "kv260-event-camera-app.py"
DEFAULT_OUTPUT_ROOT = pathlib.Path("/tmp/kv260-event-camera-validation")
DEFAULT_RECORD_DIR = pathlib.Path(
    os.path.expanduser(os.environ.get("KV260_EVENT_RECORD_DIR", "~/event_recordings"))
)


class FrameStats:
    def __init__(self, after_seconds=2.0):
        self.started = time.monotonic()
        self.after_seconds = after_seconds
        self.frames = 0
        self.changed = 0
        self.after_frames = 0
        self.after_changed = 0
        self.nonblank = 0
        self.last = None

    def on_frame(self, frame):
        now = time.monotonic()
        copied = frame.copy()
        self.frames += 1
        if np.any(copied):
            self.nonblank += 1
        if self.last is not None and np.any(self.last != copied):
            self.changed += 1
            if now - self.started >= self.after_seconds:
                self.after_changed += 1
        if now - self.started >= self.after_seconds:
            self.after_frames += 1
        self.last = copied

    def as_dict(self):
        return {
            "frames": self.frames,
            "changed": self.changed,
            "after_seconds": self.after_seconds,
            "after_frames": self.after_frames,
            "after_changed": self.after_changed,
            "nonblank": self.nonblank,
        }


def load_app():
    spec = importlib.util.spec_from_file_location("kv260_event_camera_app", APP_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def stop_existing_processes():
    stopped = []
    socket_path = os.environ.get("KV260_EVENT_CAMERA_APP_SOCKET", "/tmp/kv260-event-camera-app.sock")
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(1)
        sock.connect(socket_path)
        sock.sendall(b"quit\n")
        try:
            stopped.append(sock.recv(1024).decode("utf-8", "replace").strip())
        except Exception:
            pass
        sock.close()
        time.sleep(1)
    except Exception as exc:
        stopped.append("socket quit skipped: %s" % exc)

    stop_script = HERE / "kv260-event-visual-gui-local.sh"
    if stop_script.exists():
        subprocess.run(
            [str(stop_script), "--stop", "--force"],
            cwd=str(PROJECT_DIR),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    return stopped


def run_writer_sanity(app, output_dir):
    path = output_dir / "writer_sanity.pse2.raw"
    statuses = []
    payloads = [bytes([idx % 251]) * 4096 for idx in range(32)]
    writer = app.RawRecordingWriter(
        str(path),
        {"test": "writer_sanity", "created": time.strftime("%Y-%m-%dT%H:%M:%S")},
        statuses.append,
        queue_size=16,
    )
    writer.start()
    accepted = sum(1 for payload in payloads if writer.enqueue(payload))
    stats = writer.stop()
    file_size = path.stat().st_size if path.exists() else 0
    metadata = json.loads((pathlib.Path(str(path) + ".json")).read_text())
    return {
        "name": "writer_sanity",
        "accepted": accepted,
        "expected_drops": max(0, len(payloads) - accepted),
        "file_size": file_size,
        "stats": stats,
        "metadata_status": metadata.get("recording_status"),
        "statuses": statuses,
        "pass": bool(
            accepted > 0
            and file_size == stats["bytes_written"]
            and stats["buffers_written"] == accepted
            and stats["dropped_buffers"] == max(0, len(payloads) - accepted)
            and stats["pending_buffers"] == 0
            and stats.get("stop_elapsed_s", 0) >= 0
            and not stats["write_error"]
            and metadata.get("recording_status") == "stopped"
        ),
    }


def replay_first_chunk(app, path, bytes_to_read=1024 * 1024):
    decoder = app.EVT21Decoder()
    with open(path, "rb") as raw_file:
        payload = raw_file.read(bytes_to_read)
    batch = decoder.decode(payload)
    renderer = app.EventFrameRenderer()
    renderer.add_batch(batch)
    frame = renderer.render_frame("Playback", 0.0, False, False)
    return {
        "bytes_read": len(payload),
        "events": int(batch.count),
        "nonblank": bool(np.any(frame)),
    }


def run_live_preview(app, device, duration):
    frame_stats = FrameStats()
    statuses = []
    renderer = app.EventFrameRenderer()
    stream = app.V4L2EventStream(device, renderer, frame_stats.on_frame, statuses.append)
    stream.set_recording_priority(True)
    started = time.monotonic()
    stream.start()
    time.sleep(duration)
    stream.stop()
    elapsed = time.monotonic() - started
    result = {
        "name": "live_preview_no_recording",
        "duration_s": round(elapsed, 3),
        "frames": frame_stats.as_dict(),
        "events": int(stream.total_events),
        "buffers": int(stream.total_buffers),
        "decoded_buffers": int(stream.preview_decoded_buffers),
        "skipped_buffers": int(stream.preview_skipped_buffers),
        "preview_errors": int(stream.preview_errors),
        "statuses_tail": statuses[-5:],
    }
    result["pass"] = bool(
        result["buffers"] > 0
        and result["events"] > 0
        and result["decoded_buffers"] > 0
        and result["decoded_buffers"] < result["buffers"]
        and result["skipped_buffers"] > 0
        and result["preview_errors"] == 0
        and result["frames"]["frames"] >= 10
        and result["frames"]["after_changed"] > 0
        and result["frames"]["nonblank"] > 0
    )
    return result


def run_recording(app, device, record_dir, duration, priority):
    mode = "priority_on" if priority else "priority_off"
    path = record_dir / ("validation_%s_%s.pse2.raw" % (mode, time.strftime("%Y%m%d_%H%M%S")))
    frame_stats = FrameStats()
    statuses = []
    renderer = app.EventFrameRenderer()
    stream = app.V4L2EventStream(device, renderer, frame_stats.on_frame, statuses.append)
    stream.set_recording_priority(priority)
    stream.start()
    time.sleep(1.0)
    stream.start_recording(str(path))
    record_started = time.monotonic()
    time.sleep(duration)
    snapshot = stream.recording_snapshot() or {}
    stop_started = time.monotonic()
    stream.stop_recording()
    stop_elapsed = time.monotonic() - stop_started
    elapsed_recording = time.monotonic() - record_started
    time.sleep(0.3)
    stream.stop()

    metadata = json.loads(pathlib.Path(str(path) + ".json").read_text())
    stats = metadata.get("recording_stats", {})
    file_size = path.stat().st_size if path.exists() else 0
    replay = replay_first_chunk(app, path)
    result = {
        "name": "recording_%s" % mode,
        "recording_priority": priority,
        "duration_s": round(elapsed_recording, 3),
        "path": str(path),
        "file_size": file_size,
        "snapshot": snapshot,
        "metadata_stats": stats,
        "metadata_status": metadata.get("recording_status"),
        "frames": frame_stats.as_dict(),
        "events": int(stream.total_events),
        "buffers": int(stream.total_buffers),
        "decoded_buffers": int(stream.preview_decoded_buffers),
        "skipped_buffers": int(stream.preview_skipped_buffers),
        "preview_errors": int(stream.preview_errors),
        "replay": replay,
        "stop_recording_elapsed_s": round(stop_elapsed, 3),
        "statuses_tail": statuses[-8:],
    }
    common_pass = bool(
        file_size > 0
        and stats.get("bytes_written") == file_size
        and stats.get("buffers_written", 0) > 0
        and stats.get("pending_buffers") == 0
        and stats.get("dropped_buffers") == 0
        and stats.get("stop_elapsed_s", 0) >= 0
        and not stats.get("write_error")
        and metadata.get("recording_status") == "stopped"
        and result["preview_errors"] == 0
        and replay["events"] > 0
        and replay["nonblank"]
    )
    preview_pass = bool(
        result["decoded_buffers"] > 0
        and result["decoded_buffers"] < result["buffers"]
        and result["skipped_buffers"] > 0
        and result["frames"]["frames"] >= 5
        and result["frames"]["after_changed"] > 0
    )
    result["pass"] = bool(common_pass and preview_pass)
    return result


def run_playback_player(app, path, sample_s=4.0):
    frame_stats = FrameStats(after_seconds=0.5)
    statuses = []
    renderer = app.EventFrameRenderer()
    player = app.PSE2RecordingPlayer(str(path), renderer, frame_stats.on_frame, statuses.append)
    started = time.monotonic()
    player.start()
    deadline = started + sample_s
    observed_playback = False
    while time.monotonic() < deadline:
        observed_playback = frame_stats.nonblank > 0 and player.total_events > 0
        if observed_playback and frame_stats.frames >= 5:
            break
        time.sleep(0.1)
    stop_started = time.monotonic()
    player.stop()
    stop_elapsed = time.monotonic() - stop_started
    elapsed = time.monotonic() - started
    result = {
        "name": "playback_player",
        "path": str(path),
        "duration_s": round(elapsed, 3),
        "sample_s": sample_s,
        "observed_playback": observed_playback,
        "stop_elapsed_s": round(stop_elapsed, 3),
        "events": int(player.total_events),
        "rate_mev_s": float(player.rate_mev_s),
        "frames": frame_stats.as_dict(),
        "statuses_tail": statuses[-8:],
    }
    result["pass"] = bool(
        observed_playback
        and result["events"] > 0
        and result["frames"]["frames"] >= 5
        and result["frames"]["nonblank"] > 0
        and result["stop_elapsed_s"] < 4.0
    )
    return result


def run_bias_probe(app):
    expected = {"bias_diff_on", "bias_diff_off", "bias_hpf", "bias_fo", "bias_refr", "bias_diff"}
    controller = app.BiasController()
    try:
        controls = controller.read_controls()
        found = sorted(controls)
        missing = sorted(expected - set(controls))
        error = None
    except Exception as exc:
        found = []
        missing = sorted(expected)
        error = str(exc)
    return {
        "name": "bias_probe",
        "device": controller.device,
        "found": found,
        "missing": missing,
        "error": error,
        "pass": bool(not error and not missing),
    }


def run_launcher_probe():
    entries = [
        pathlib.Path("/usr/share/applications/kv260-event-camera.desktop"),
        pathlib.Path("/usr/share/applications/kv260-file-transfer.desktop"),
    ]
    scripts = [
        HERE / "kv260-event-camera-app.sh",
        HERE / "kv260-file-transfer-gui.sh",
        HERE / "kv260-event-camera-switch.sh",
    ]
    missing_entries = [str(path) for path in entries if not path.exists()]
    missing_scripts = [str(path) for path in scripts if not path.exists()]
    non_exec_scripts = [str(path) for path in scripts if path.exists() and not os.access(path, os.X_OK)]
    return {
        "name": "launcher_probe",
        "entries": [str(path) for path in entries],
        "scripts": [str(path) for path in scripts],
        "missing_entries": missing_entries,
        "missing_scripts": missing_scripts,
        "non_exec_scripts": non_exec_scripts,
        "pass": bool(not missing_entries and not missing_scripts and not non_exec_scripts),
    }


def run_gui_smoke(output_dir):
    display = os.environ.get("DISPLAY", ":0")
    socket_path = output_dir / "gui-smoke.sock"
    lock_path = output_dir / "gui-smoke.lock"
    log_path = output_dir / "gui-smoke.log"
    env = os.environ.copy()
    env.update(
        {
            "DISPLAY": display,
            "KV260_EVENT_APP_AUTO_OPEN": "0",
            "KV260_EVENT_CAMERA_APP_SOCKET": str(socket_path),
            "KV260_EVENT_CAMERA_APP_LOCK_PATH": str(lock_path),
        }
    )
    with open(log_path, "wb") as log_file:
        proc = subprocess.Popen([sys.executable, str(APP_PATH)], cwd=str(PROJECT_DIR), env=env, stdout=log_file, stderr=log_file)
    connected = False
    response = ""
    last_error = ""
    for _ in range(30):
        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(1)
            sock.connect(str(socket_path))
            sock.sendall(b"quit\n")
            try:
                response = sock.recv(1024).decode("utf-8", "replace").strip()
            except Exception:
                pass
            sock.close()
            connected = True
            break
        except Exception as exc:
            last_error = str(exc)
            time.sleep(0.2)
    try:
        return_code = proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.terminate()
        return_code = proc.wait(timeout=5)
    log_tail = ""
    try:
        log_tail = "\n".join(log_path.read_text(errors="replace").splitlines()[-12:])
    except Exception:
        pass
    return {
        "name": "gui_smoke",
        "display": display,
        "connected_to_socket": connected,
        "socket_response": response,
        "last_error": last_error,
        "return_code": return_code,
        "log_path": str(log_path),
        "log_tail": log_tail,
        "pass": bool(connected and return_code == 0),
    }


def write_reports(output_dir, results):
    json_path = output_dir / "report.json"
    md_path = output_dir / "report.md"
    json_path.write_text(json.dumps(results, indent=2, sort_keys=True) + "\n")

    lines = [
        "# KV260 Event Camera Validation",
        "",
        "Generated: `%s`" % results["generated"],
        "",
        "Overall result: `%s`" % ("PASS" if results["pass"] else "FAIL"),
        "",
        "## Checks",
        "",
    ]
    for item in results["checks"]:
        lines.append("- `%s`: `%s`" % (item["name"], "PASS" if item.get("pass") else "FAIL"))
    lines.extend(["", "## Key Results", ""])
    for item in results["checks"]:
        lines.append("### %s" % item["name"])
        if item["name"] == "live_preview_no_recording":
            lines.append(
                "- buffers=%s decoded=%s skipped=%s preview_errors=%s frames=%s changed_after_2s=%s"
                % (
                    item["buffers"],
                    item["decoded_buffers"],
                    item["skipped_buffers"],
                    item["preview_errors"],
                    item["frames"]["frames"],
                    item["frames"]["after_changed"],
                )
            )
        elif item["name"].startswith("recording_"):
            stats = item["metadata_stats"]
            lines.append(
                "- file_size=%s bytes_written=%s buffers=%s queue_pending=%s drops=%s write_error=%s stop_elapsed=%s"
                % (
                    item["file_size"],
                    stats.get("bytes_written"),
                    stats.get("buffers_written"),
                    stats.get("pending_buffers"),
                    stats.get("dropped_buffers"),
                    stats.get("write_error"),
                    stats.get("stop_elapsed_s"),
                )
            )
            lines.append(
                "- decoded=%s skipped=%s priority=%s replay_events=%s replay_nonblank=%s"
                % (
                    item["decoded_buffers"],
                    item["skipped_buffers"],
                    item["recording_priority"],
                    item["replay"]["events"],
                    item["replay"]["nonblank"],
                )
            )
            lines.append("- path=`%s`" % item["path"])
        elif item["name"] == "writer_sanity":
            lines.append(
                "- accepted=%s file_size=%s bytes_written=%s pending=%s drops=%s stop_elapsed=%s"
                % (
                    item["accepted"],
                    item["file_size"],
                    item["stats"].get("bytes_written"),
                    item["stats"].get("pending_buffers"),
                    item["stats"].get("dropped_buffers"),
                    item["stats"].get("stop_elapsed_s"),
                )
            )
        elif item["name"] == "playback_player":
            lines.append(
                "- events=%s frames=%s nonblank=%s observed=%s stop_elapsed=%s path=`%s`"
                % (
                    item["events"],
                    item["frames"]["frames"],
                    item["frames"]["nonblank"],
                    item["observed_playback"],
                    item["stop_elapsed_s"],
                    item["path"],
                )
            )
        elif item["name"] == "bias_probe":
            lines.append(
                "- device=%s found=%s missing=%s error=%s"
                % (item["device"], len(item["found"]), item["missing"], item["error"])
            )
        elif item["name"] == "launcher_probe":
            lines.append(
                "- entries_ok=%s scripts_ok=%s executable_ok=%s"
                % (
                    not item["missing_entries"],
                    not item["missing_scripts"],
                    not item["non_exec_scripts"],
                )
            )
        elif item["name"] == "gui_smoke":
            lines.append(
                "- display=%s socket=%s return_code=%s"
                % (item["display"], item["connected_to_socket"], item["return_code"])
            )
        lines.append("")
    md_path.write_text("\n".join(lines) + "\n")
    return json_path, md_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default="/dev/video0")
    parser.add_argument("--output-root", default=str(DEFAULT_OUTPUT_ROOT))
    parser.add_argument("--record-dir", default=str(DEFAULT_RECORD_DIR))
    parser.add_argument("--live-seconds", type=float, default=5.0)
    parser.add_argument("--record-seconds", type=float, default=6.0)
    parser.add_argument("--no-stop-existing", action="store_true")
    parser.add_argument("--skip-gui-smoke", action="store_true")
    args = parser.parse_args()

    output_dir = pathlib.Path(args.output_root) / time.strftime("%Y%m%d-%H%M%S")
    output_dir.mkdir(parents=True, exist_ok=True)
    record_dir = pathlib.Path(args.record_dir)
    record_dir.mkdir(parents=True, exist_ok=True)

    app = load_app()
    checks = []
    stopped = [] if args.no_stop_existing else stop_existing_processes()

    checks.append(run_writer_sanity(app, output_dir))
    checks.append(run_launcher_probe())
    checks.append(run_bias_probe(app))
    checks.append(run_live_preview(app, args.device, args.live_seconds))
    priority_on = run_recording(app, args.device, record_dir, args.record_seconds, True)
    checks.append(priority_on)
    checks.append(run_playback_player(app, priority_on["path"]))
    checks.append(run_recording(app, args.device, record_dir, args.record_seconds, False))
    if not args.skip_gui_smoke:
        checks.append(run_gui_smoke(output_dir))

    results = {
        "generated": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "project_dir": str(PROJECT_DIR),
        "device": args.device,
        "output_dir": str(output_dir),
        "record_dir": str(record_dir),
        "stopped_existing": stopped,
        "checks": checks,
    }
    results["pass"] = all(item.get("pass") for item in checks)
    json_path, md_path = write_reports(output_dir, results)
    print("VALIDATION_REPORT_JSON=%s" % json_path)
    print("VALIDATION_REPORT_MD=%s" % md_path)
    print("VALIDATION_RESULT=%s" % ("PASS" if results["pass"] else "FAIL"))
    for item in checks:
        print("%s=%s" % (item["name"], "PASS" if item.get("pass") else "FAIL"))
    return 0 if results["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
