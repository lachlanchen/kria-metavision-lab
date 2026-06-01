#!/usr/bin/env python3
"""KV260 Prophesee event-camera app.

This app reads the PSE2/EVT2.1 V4L2 node directly, renders live events with
GTK, records the raw PSE2 byte stream with a JSON sidecar, and replays those
recordings without requiring the Metavision Python bindings.
"""

import ctypes
import fcntl
import json
import mmap
import os
import queue
import re
import select
import socket
import subprocess
import threading
import time
from datetime import datetime

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk

import numpy as np

try:
    from PIL import Image, ImageDraw, ImageFont
except Exception:  # pragma: no cover - the app works without the OSD overlay.
    Image = None
    ImageDraw = None
    ImageFont = None


HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(HERE)
DEFAULT_DEVICE = "/dev/video0"
DEFAULT_BIAS_DEVICE = "/dev/v4l-subdev3"
WIDTH = 1280
HEIGHT = 720
VIEW_W = 960
VIEW_H = 540
DEFAULT_RECORD_DIR = os.path.expanduser(os.environ.get("KV260_EVENT_RECORD_DIR", "~/event_recordings"))
APP_LOCK_PATH = os.environ.get("KV260_EVENT_CAMERA_APP_LOCK_PATH", "/tmp/kv260-event-camera-app.lock")
APP_SOCKET_PATH = os.environ.get("KV260_EVENT_CAMERA_APP_SOCKET", "/tmp/kv260-event-camera-app.sock")
DEFAULT_RECORD_QUEUE_BUFFERS = int(os.environ.get("KV260_RECORD_QUEUE_BUFFERS", "256"))


_IOC_NRBITS = 8
_IOC_TYPEBITS = 8
_IOC_SIZEBITS = 14
_IOC_NRSHIFT = 0
_IOC_TYPESHIFT = _IOC_NRSHIFT + _IOC_NRBITS
_IOC_SIZESHIFT = _IOC_TYPESHIFT + _IOC_TYPEBITS
_IOC_DIRSHIFT = _IOC_SIZESHIFT + _IOC_SIZEBITS
_IOC_WRITE = 1
_IOC_READ = 2


def _ioc(direction, type_char, nr, size):
    return (
        (direction << _IOC_DIRSHIFT)
        | (ord(type_char) << _IOC_TYPESHIFT)
        | (nr << _IOC_NRSHIFT)
        | (size << _IOC_SIZESHIFT)
    )


def _iowr(type_char, nr, typ):
    return _ioc(_IOC_READ | _IOC_WRITE, type_char, nr, ctypes.sizeof(typ))


def _iow(type_char, nr, typ):
    return _ioc(_IOC_WRITE, type_char, nr, ctypes.sizeof(typ))


class Timeval(ctypes.Structure):
    _fields_ = [("tv_sec", ctypes.c_long), ("tv_usec", ctypes.c_long)]


class Timecode(ctypes.Structure):
    _fields_ = [
        ("type", ctypes.c_uint32),
        ("flags", ctypes.c_uint32),
        ("frames", ctypes.c_uint8),
        ("seconds", ctypes.c_uint8),
        ("minutes", ctypes.c_uint8),
        ("hours", ctypes.c_uint8),
        ("userbits", ctypes.c_uint8 * 4),
    ]


class BufferMemory(ctypes.Union):
    _fields_ = [
        ("offset", ctypes.c_uint32),
        ("userptr", ctypes.c_ulong),
        ("planes", ctypes.c_void_p),
        ("fd", ctypes.c_int32),
    ]


class V4L2Buffer(ctypes.Structure):
    _fields_ = [
        ("index", ctypes.c_uint32),
        ("type", ctypes.c_uint32),
        ("bytesused", ctypes.c_uint32),
        ("flags", ctypes.c_uint32),
        ("field", ctypes.c_uint32),
        ("timestamp", Timeval),
        ("timecode", Timecode),
        ("sequence", ctypes.c_uint32),
        ("memory", ctypes.c_uint32),
        ("m", BufferMemory),
        ("length", ctypes.c_uint32),
        ("reserved2", ctypes.c_uint32),
        ("request_fd", ctypes.c_int32),
    ]


class RequestBuffers(ctypes.Structure):
    _fields_ = [
        ("count", ctypes.c_uint32),
        ("type", ctypes.c_uint32),
        ("memory", ctypes.c_uint32),
        ("reserved", ctypes.c_uint32 * 2),
    ]


V4L2_BUF_TYPE_VIDEO_CAPTURE = 1
V4L2_MEMORY_MMAP = 1
VIDIOC_REQBUFS = _iowr("V", 8, RequestBuffers)
VIDIOC_QUERYBUF = _iowr("V", 9, V4L2Buffer)
VIDIOC_QBUF = _iowr("V", 15, V4L2Buffer)
VIDIOC_DQBUF = _iowr("V", 17, V4L2Buffer)
VIDIOC_STREAMON = _iow("V", 18, ctypes.c_int)
VIDIOC_STREAMOFF = _iow("V", 19, ctypes.c_int)


PALETTES = {
    "Dark": {
        "bg": (8, 12, 18),
        "on": (70, 220, 135),
        "off": (255, 92, 82),
        "text": (230, 235, 245),
        "panel": (20, 27, 38),
    },
    "Light": {
        "bg": (246, 248, 251),
        "on": (10, 105, 170),
        "off": (210, 48, 64),
        "text": (20, 25, 35),
        "panel": (235, 239, 245),
    },
    "Gray": {
        "bg": (128, 128, 128),
        "on": (255, 255, 255),
        "off": (0, 0, 0),
        "text": (255, 255, 255),
        "panel": (72, 72, 72),
    },
    "CoolWarm": {
        "bg": (13, 20, 33),
        "on": (68, 180, 255),
        "off": (255, 142, 66),
        "text": (234, 241, 255),
        "panel": (24, 33, 48),
    },
}


BIAS_HELP = {
    "bias_diff_on": "ON contrast threshold. Increase to reduce ON events; decrease for more ON sensitivity.",
    "bias_diff_off": "OFF contrast threshold. Increase to reduce OFF events on IMX636/GenX320.",
    "bias_hpf": "High-pass filter. Lower values keep slower changes; higher values suppress slow background activity.",
    "bias_fo": "Low-pass bandwidth. Tune first when flicker or fast light changes dominate the stream.",
    "bias_refr": "Refractory period after each event. Use carefully to reduce bursts during large changes.",
    "bias_diff": "Reference contrast bias. Usually leave at default unless you are doing expert tuning.",
}


COMMON_BIASES = ("bias_diff_on", "bias_diff_off", "bias_hpf", "bias_fo", "bias_refr", "bias_diff")


class EventBatch:
    def __init__(self, x, y, polarity, timestamp):
        self.x = x
        self.y = y
        self.polarity = polarity
        self.timestamp = timestamp
        self.count = int(len(x))
        if self.count and timestamp.size:
            self.t_min = int(timestamp.min())
            self.t_max = int(timestamp.max())
        else:
            self.t_min = 0
            self.t_max = 0


class EVT21Decoder:
    """Vectorized decoder for the KV260 PSE2/EVT2.1 byte stream."""

    def __init__(self):
        self.current_time_high = np.uint64(0)
        self.last_high_raw = np.uint64(0)
        self.high_loop = np.uint64(0)
        self.base_time_set = False

    def reset(self):
        self.current_time_high = np.uint64(0)
        self.last_high_raw = np.uint64(0)
        self.high_loop = np.uint64(0)
        self.base_time_set = False

    def _high_timestamp_from_words(self, words):
        high_raw = (words >> np.uint64(32)) & np.uint64(0x0FFFFFFF)
        return high_raw << np.uint64(6)

    def decode(self, payload):
        usable = len(payload) - (len(payload) % 8)
        if usable <= 0:
            return EventBatch(
                np.empty(0, dtype=np.int16),
                np.empty(0, dtype=np.int16),
                np.empty(0, dtype=np.bool_),
                np.empty(0, dtype=np.int64),
            )

        words = np.frombuffer(payload[:usable], dtype="<u8")
        event_type = (words >> np.uint64(60)) & np.uint64(0xF)
        time_high_mask = event_type == np.uint64(8)
        if np.any(time_high_mask):
            high_values = self._high_timestamp_from_words(words)
            high_positions = np.where(time_high_mask)[0]
            high_at_word = np.where(time_high_mask, np.arange(words.size), -1)
            last_high_index = np.maximum.accumulate(high_at_word)
            time_base = np.full(words.size, self.current_time_high, dtype=np.uint64)
            has_seen_high = last_high_index >= 0
            time_base[has_seen_high] = high_values[last_high_index[has_seen_high]]
            self.current_time_high = np.uint64(high_values[high_positions[-1]])
            self.base_time_set = True
        else:
            time_base = np.full(words.size, self.current_time_high, dtype=np.uint64)

        cd = (
            (event_type == np.uint64(0))
            | (event_type == np.uint64(1))
            | (event_type == np.uint64(4))
            | (event_type == np.uint64(5))
        )
        if not np.any(cd):
            return EventBatch(
                np.empty(0, dtype=np.int16),
                np.empty(0, dtype=np.int16),
                np.empty(0, dtype=np.bool_),
                np.empty(0, dtype=np.int64),
            )

        cd_words = words[cd]
        cd_type = event_type[cd]
        cd_time_base = time_base[cd]
        ts_low = (cd_words >> np.uint64(54)) & np.uint64(0x3F)
        timestamp = (cd_time_base + ts_low).astype(np.int64)
        x_base = ((cd_words >> np.uint64(43)) & np.uint64(0x7FF)).astype(np.int32)
        y_base = ((cd_words >> np.uint64(32)) & np.uint64(0x7FF)).astype(np.int32)
        vx = (cd_words & np.uint64(0xFFFFFFFF)).astype(np.uint32)
        valid = (x_base >= 0) & (x_base < WIDTH) & (y_base >= 0) & (y_base < HEIGHT) & (vx != 0)
        if not np.any(valid):
            return EventBatch(
                np.empty(0, dtype=np.int16),
                np.empty(0, dtype=np.int16),
                np.empty(0, dtype=np.bool_),
                np.empty(0, dtype=np.int64),
            )

        x_base = x_base[valid]
        y_base = y_base[valid]
        vx = vx[valid]
        cd_type = cd_type[valid]
        timestamp = timestamp[valid]

        xs = []
        ys = []
        pols = []
        tss = []
        for bit in range(32):
            bit_mask = ((vx >> np.uint32(bit)) & np.uint32(1)) != 0
            if not np.any(bit_mask):
                continue
            xs.append(x_base[bit_mask] + bit)
            ys.append(y_base[bit_mask])
            pols.append((cd_type[bit_mask] == np.uint64(1)) | (cd_type[bit_mask] == np.uint64(5)))
            tss.append(timestamp[bit_mask])

        if not xs:
            return EventBatch(
                np.empty(0, dtype=np.int16),
                np.empty(0, dtype=np.int16),
                np.empty(0, dtype=np.bool_),
                np.empty(0, dtype=np.int64),
            )

        x = np.concatenate(xs)
        y = np.concatenate(ys)
        polarity = np.concatenate(pols)
        timestamp = np.concatenate(tss)
        valid_xy = (x >= 0) & (x < WIDTH) & (y >= 0) & (y < HEIGHT)
        if not np.any(valid_xy):
            return EventBatch(
                np.empty(0, dtype=np.int16),
                np.empty(0, dtype=np.int16),
                np.empty(0, dtype=np.bool_),
                np.empty(0, dtype=np.int64),
            )

        return EventBatch(
            x[valid_xy].astype(np.int16, copy=False),
            y[valid_xy].astype(np.int16, copy=False),
            polarity[valid_xy].astype(np.bool_, copy=False),
            timestamp[valid_xy].astype(np.int64, copy=False),
        )


class EventFrameRenderer:
    """Metavision-style accumulation renderer shared by live and replay modes."""

    def __init__(self):
        self.lock = threading.Lock()
        self.batches = []
        self.last_event_ts = 0
        self.total_events = 0
        self.accumulation_us = 10000
        self.fps = 30
        self.palette_name = "Dark"
        self.polarity_mode = "All"
        self.point_radius = 1
        self.trail = 0.82
        self.show_osd = True
        self.last_frame = None
        self.last_batch_wall_time = 0.0
        self.osd_font = None
        if ImageFont is not None:
            try:
                self.osd_font = ImageFont.load_default()
            except Exception:
                self.osd_font = None

    def reset(self):
        with self.lock:
            self.batches = []
            self.last_event_ts = 0
            self.total_events = 0
            self.last_frame = None
            self.last_batch_wall_time = 0.0

    def snapshot_settings(self):
        with self.lock:
            return {
                "accumulation_us": self.accumulation_us,
                "fps": self.fps,
                "palette": self.palette_name,
                "polarity": self.polarity_mode,
                "point_radius": self.point_radius,
                "trail": self.trail,
                "show_osd": self.show_osd,
            }

    def configure(self, accumulation_ms=None, fps=None, palette=None, polarity=None, point_radius=None, trail=None, osd=None):
        with self.lock:
            if accumulation_ms is not None:
                self.accumulation_us = max(1000, min(500000, int(float(accumulation_ms) * 1000)))
            if fps is not None:
                self.fps = max(1, min(90, int(float(fps))))
            if palette in PALETTES:
                self.palette_name = palette
            if polarity in ("All", "ON", "OFF"):
                self.polarity_mode = polarity
            if point_radius is not None:
                self.point_radius = max(0, min(4, int(point_radius)))
            if trail is not None:
                self.trail = max(0.0, min(0.995, float(trail)))
            if osd is not None:
                self.show_osd = bool(osd)

    def add_batch(self, batch):
        if batch.count <= 0:
            return
        with self.lock:
            self.batches.append(batch)
            self.total_events += batch.count
            self.last_event_ts = max(self.last_event_ts, batch.t_max)
            self.last_batch_wall_time = time.monotonic()
            cutoff = self.last_event_ts - max(self.accumulation_us, 250000)
            if cutoff > 0:
                self.batches = [item for item in self.batches if item.t_max >= cutoff]
            if len(self.batches) > 240:
                self.batches = self.batches[-240:]

    def render_frame(self, source_label, rate_mev_s=0.0, recording=False, paused=False):
        with self.lock:
            settings = {
                "accumulation_us": self.accumulation_us,
                "fps": self.fps,
                "palette": self.palette_name,
                "polarity": self.polarity_mode,
                "point_radius": self.point_radius,
                "trail": self.trail,
                "show_osd": self.show_osd,
            }
            palette = PALETTES.get(settings["palette"], PALETTES["Dark"])
            bg = np.array(palette["bg"], dtype=np.uint8)
            display_ts = self.last_event_ts
            if display_ts and not paused and self.last_batch_wall_time:
                idle_us = int(max(0.0, time.monotonic() - self.last_batch_wall_time) * 1_000_000)
                display_ts += min(idle_us, max(settings["accumulation_us"] * 4, 250000))
            cutoff = display_ts - settings["accumulation_us"]
            batches = [batch for batch in self.batches if batch.t_max >= cutoff]
            if self.last_frame is not None and settings["trail"] > 0:
                frame = (
                    self.last_frame.astype(np.float32) * settings["trail"]
                    + bg.astype(np.float32) * (1.0 - settings["trail"])
                ).astype(np.uint8)
            else:
                frame = np.empty((VIEW_H, VIEW_W, 3), dtype=np.uint8)
                frame[:, :] = bg

            for batch in batches:
                mask = batch.timestamp >= cutoff
                if settings["polarity"] == "ON":
                    mask &= batch.polarity
                elif settings["polarity"] == "OFF":
                    mask &= ~batch.polarity
                if not np.any(mask):
                    continue
                x = ((batch.x[mask].astype(np.int32) * VIEW_W) // WIDTH).clip(0, VIEW_W - 1)
                y = ((batch.y[mask].astype(np.int32) * VIEW_H) // HEIGHT).clip(0, VIEW_H - 1)
                pol = batch.polarity[mask]
                self._draw_events(frame, x, y, pol, palette, settings["point_radius"])

            if settings["show_osd"]:
                rec_text = " REC" if recording else ""
                pause_text = " PAUSED" if paused else ""
                osd = "%s%s%s | %.2f Mev/s | acc %.1f ms | %s" % (
                    source_label,
                    rec_text,
                    pause_text,
                    rate_mev_s,
                    settings["accumulation_us"] / 1000.0,
                    settings["polarity"],
                )
                frame = self._draw_osd(frame, osd, palette)

            self.last_frame = frame.copy()
            return frame

    def _draw_events(self, frame, x, y, polarity, palette, radius):
        radius = max(0, min(4, int(radius)))
        off = ~polarity
        on = polarity
        on_color = palette["on"]
        off_color = palette["off"]
        if radius == 0:
            if np.any(off):
                frame[y[off], x[off]] = off_color
            if np.any(on):
                frame[y[on], x[on]] = on_color
            return

        for dy in range(-radius, radius + 1):
            yy = (y + dy).clip(0, VIEW_H - 1)
            for dx in range(-radius, radius + 1):
                xx = (x + dx).clip(0, VIEW_W - 1)
                if np.any(off):
                    frame[yy[off], xx[off]] = off_color
                if np.any(on):
                    frame[yy[on], xx[on]] = on_color

    def _draw_osd(self, frame, text, palette):
        if Image is None or ImageDraw is None:
            return frame
        try:
            image = Image.fromarray(frame)
            draw = ImageDraw.Draw(image)
            width = max(260, min(VIEW_W - 20, 9 * len(text) + 18))
            draw.rectangle((10, 9, width, 32), fill=palette["panel"])
            draw.text((18, 15), text, fill=palette["text"], font=self.osd_font)
            return np.asarray(image).copy()
        except Exception:
            return frame


class RawRecordingWriter:
    def __init__(self, path, metadata, on_status, queue_size=DEFAULT_RECORD_QUEUE_BUFFERS):
        self.path = path
        self.meta_path = path + ".json"
        self.metadata = dict(metadata)
        self.on_status = on_status
        self.queue_size = max(8, int(queue_size))
        self.queue = queue.Queue(maxsize=self.queue_size)
        self.file = None
        self.thread = None
        self.stats_lock = threading.Lock()
        self.queued_buffers = 0
        self.queued_bytes = 0
        self.buffers_written = 0
        self.bytes_written = 0
        self.dropped_buffers = 0
        self.dropped_bytes = 0
        self.write_error = None

    def start(self):
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        self.metadata.update(
            {
                "recording_backend": "bounded-python-raw-writer",
                "record_queue_buffers": self.queue_size,
                "recording_status": "recording",
            }
        )
        self._write_metadata()
        self.file = open(self.path, "wb", buffering=1024 * 1024)
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def enqueue(self, payload):
        try:
            self.queue.put_nowait(payload)
            with self.stats_lock:
                self.queued_buffers += 1
                self.queued_bytes += len(payload)
            return True
        except queue.Full:
            with self.stats_lock:
                self.dropped_buffers += 1
                self.dropped_bytes += len(payload)
            return False

    def stop(self):
        started = time.monotonic()
        if self.thread and self.thread.is_alive():
            while self.thread.is_alive():
                try:
                    self.queue.put(None, timeout=0.2)
                    break
                except queue.Full:
                    continue
            self.thread.join()
        elif self.file:
            self._close_file()
        stats = self.snapshot()
        stats["stop_elapsed_s"] = round(time.monotonic() - started, 3)
        self.metadata.update({"recording_status": "stopped", "recording_stats": stats})
        self._write_metadata()
        return stats

    def snapshot(self):
        with self.stats_lock:
            pending = self.queue.qsize()
            return {
                "queue_size": self.queue_size,
                "queued_buffers": self.queued_buffers,
                "queued_bytes": self.queued_bytes,
                "buffers_written": self.buffers_written,
                "bytes_written": self.bytes_written,
                "dropped_buffers": self.dropped_buffers,
                "dropped_bytes": self.dropped_bytes,
                "pending_buffers": pending,
                "write_error": self.write_error,
            }

    def _run(self):
        try:
            while True:
                payload = self.queue.get()
                try:
                    if payload is None:
                        return
                    self.file.write(payload)
                    with self.stats_lock:
                        self.buffers_written += 1
                        self.bytes_written += len(payload)
                finally:
                    self.queue.task_done()
        except Exception as exc:
            with self.stats_lock:
                self.write_error = str(exc)
            self.on_status("Recording writer failed: %s" % exc)
        finally:
            self._close_file()

    def _close_file(self):
        if self.file:
            self.file.flush()
            self.file.close()
            self.file = None

    def _write_metadata(self):
        with open(self.meta_path, "w", encoding="utf-8") as meta_file:
            json.dump(self.metadata, meta_file, indent=2)
            meta_file.write("\n")


class V4L2EventStream:
    def __init__(self, device, renderer, on_frame, on_status):
        self.device = device
        self.renderer = renderer
        self.on_frame = on_frame
        self.on_status = on_status
        self.stop_event = threading.Event()
        self.thread = None
        self.fd = None
        self.buffers = []
        self.display = np.zeros((VIEW_H, VIEW_W, 3), dtype=np.uint8)
        self.point_radius = 1
        self.decay = 0.82
        self.frame_interval = 0.033
        self.polarity_mode = "All"
        self.on_color = (60, 210, 130)
        self.off_color = (230, 80, 60)
        self.record_lock = threading.Lock()
        self.record_writer = None
        self.record_path = None
        self.record_bytes = 0
        self.record_events = 0
        self.total_events = 0
        self.total_buffers = 0
        self.rate_mev_s = 0.0
        self.preview_errors = 0
        self.preview_decoded_buffers = 0
        self.preview_skipped_buffers = 0
        self.recording_priority = True

    def apply_render_settings(self, settings):
        self.point_radius = max(0, min(4, int(settings.get("point_radius", self.point_radius))))
        self.decay = max(0.0, min(0.995, float(settings.get("trail", self.decay))))
        fps = max(1, min(90, int(settings.get("fps", round(1.0 / self.frame_interval)))))
        self.frame_interval = 1.0 / fps
        polarity = settings.get("polarity", self.polarity_mode)
        if polarity in ("All", "ON", "OFF"):
            self.polarity_mode = polarity
        palette = PALETTES.get(settings.get("palette", "Dark"), PALETTES["Dark"])
        self.on_color = palette["on"]
        self.off_color = palette["off"]

    def start(self):
        self.stop_event.clear()
        self.total_events = 0
        self.total_buffers = 0
        self.rate_mev_s = 0.0
        self.preview_errors = 0
        self.preview_decoded_buffers = 0
        self.preview_skipped_buffers = 0
        self.display[:] = 0
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def stop(self):
        self.stop_event.set()
        if self.thread:
            self.thread.join(timeout=3.0)
        self.stop_recording()

    def is_recording(self):
        with self.record_lock:
            return self.record_writer is not None

    def set_recording_priority(self, enabled):
        self.recording_priority = bool(enabled)

    def recording_snapshot(self):
        with self.record_lock:
            writer = self.record_writer
            record_bytes = self.record_bytes
            record_events = self.record_events
        if not writer:
            return None
        stats = writer.snapshot()
        stats.update(
            {
                "accepted_bytes": record_bytes,
                "record_events": record_events,
                "preview_decoded_buffers": self.preview_decoded_buffers,
                "preview_skipped_buffers": self.preview_skipped_buffers,
                "preview_errors": self.preview_errors,
                "total_buffers": self.total_buffers,
                "recording_priority": self.recording_priority,
            }
        )
        return stats

    def start_recording(self, path):
        metadata = {
            "created": datetime.now().isoformat(timespec="seconds"),
            "format": "PSEE_EVT21",
            "pixel_format": "PSE2",
            "width": WIDTH,
            "height": HEIGHT,
            "device": self.device,
            "renderer": self.renderer.snapshot_settings(),
            "note": "Raw V4L2 PSE2/EVT2.1 byte stream captured directly from the KV260 event node.",
        }
        writer = RawRecordingWriter(path, metadata, self.on_status)
        writer.start()
        with self.record_lock:
            old_writer = self.record_writer
            self.record_writer = writer
            self.record_path = path
            self.record_bytes = 0
            self.record_events = 0
        if old_writer:
            self._finish_recording(old_writer)
        self.on_status("Recording raw PSE2 stream to %s" % path)

    def stop_recording(self):
        with self.record_lock:
            writer = self.record_writer
            self.record_writer = None
            self.record_path = None
        if writer:
            self._finish_recording(writer)

    def _finish_recording(self, writer):
        stats = writer.stop()
        self.on_status(
            "Recording stopped: %s bytes, %s buffers, drops=%s, drain=%.3fs -> %s"
            % (
                stats["bytes_written"],
                stats["buffers_written"],
                stats["dropped_buffers"],
                stats.get("stop_elapsed_s", 0.0),
                writer.path,
            )
        )

    def _open_device(self):
        self.fd = os.open(self.device, os.O_RDWR | os.O_NONBLOCK)
        req = RequestBuffers(4, V4L2_BUF_TYPE_VIDEO_CAPTURE, V4L2_MEMORY_MMAP)
        fcntl.ioctl(self.fd, VIDIOC_REQBUFS, req)
        if req.count < 2:
            raise RuntimeError("V4L2 did not allocate enough buffers")
        for index in range(req.count):
            buf = V4L2Buffer()
            buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE
            buf.memory = V4L2_MEMORY_MMAP
            buf.index = index
            fcntl.ioctl(self.fd, VIDIOC_QUERYBUF, buf)
            mm = mmap.mmap(
                self.fd,
                buf.length,
                mmap.MAP_SHARED,
                mmap.PROT_READ | mmap.PROT_WRITE,
                offset=buf.m.offset,
            )
            self.buffers.append(mm)
            fcntl.ioctl(self.fd, VIDIOC_QBUF, buf)
        stream_type = ctypes.c_int(V4L2_BUF_TYPE_VIDEO_CAPTURE)
        fcntl.ioctl(self.fd, VIDIOC_STREAMON, stream_type)

    def _close_device(self):
        if self.fd is not None:
            try:
                stream_type = ctypes.c_int(V4L2_BUF_TYPE_VIDEO_CAPTURE)
                fcntl.ioctl(self.fd, VIDIOC_STREAMOFF, stream_type)
            except OSError:
                pass
        for mm in self.buffers:
            try:
                mm.close()
            except Exception:
                pass
        self.buffers = []
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None

    def _run(self):
        try:
            self._open_device()
            self.on_status("Live camera open: %s (%sx%s PSE2)" % (self.device, WIDTH, HEIGHT))
            last_frame_time = 0.0
            last_rate_time = time.monotonic()
            last_rate_events = 0
            while not self.stop_event.is_set():
                ready, _, _ = select.select([self.fd], [], [], 0.2)
                if not ready:
                    continue

                buf = V4L2Buffer()
                buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE
                buf.memory = V4L2_MEMORY_MMAP
                try:
                    fcntl.ioctl(self.fd, VIDIOC_DQBUF, buf)
                except BlockingIOError:
                    continue

                try:
                    payload = bytes(self.buffers[buf.index][: buf.bytesused])
                finally:
                    fcntl.ioctl(self.fd, VIDIOC_QBUF, buf)

                self.total_buffers += 1

                now = time.monotonic()
                frame_due = now - last_frame_time > self.frame_interval
                recording_enabled = False
                recording_queued = False
                with self.record_lock:
                    if self.record_writer:
                        recording_enabled = True
                        recording_queued = self.record_writer.enqueue(payload)
                        if recording_queued:
                            self.record_bytes += len(payload)

                events = 0
                decode_preview = (not recording_enabled) or (not self.recording_priority) or frame_due
                if decode_preview:
                    try:
                        events = self._decode_and_draw(payload)
                        self.preview_decoded_buffers += 1
                    except Exception as exc:
                        self.preview_errors += 1
                        if self.preview_errors <= 3:
                            self.on_status("Preview decode failed; recording continues: %s" % exc)
                else:
                    self.preview_skipped_buffers += 1

                self.total_events += events
                if recording_queued:
                    with self.record_lock:
                        self.record_events += events

                if frame_due:
                    last_frame_time = now
                    self.on_frame(self.display.copy())
                    self.display[:] = (self.display.astype(np.float32) * self.decay).astype(np.uint8)
                if now - last_rate_time >= 1.0:
                    delta_events = self.total_events - last_rate_events
                    last_rate_events = self.total_events
                    last_rate_time = now
                    self.rate_mev_s = delta_events / 1_000_000.0
                    rec = " recording" if self.is_recording() else ""
                    preview_skip = (
                        ", preview skip=%s" % self.preview_skipped_buffers
                        if self.preview_skipped_buffers
                        else ""
                    )
                    self.on_status(
                        "Live: %.2f Mev/s, buffers=%s%s%s"
                        % (self.rate_mev_s, self.total_buffers, rec, preview_skip)
                    )
        except Exception as exc:
            self.on_status("Camera stream failed: %s" % exc)
        finally:
            self._close_device()
            self.stop_recording()
            self.on_status("Camera stream closed.")

    def _decode_and_draw(self, payload):
        usable = len(payload) - (len(payload) % 8)
        if usable <= 0:
            return 0

        words = np.frombuffer(payload[:usable], dtype="<u8")
        event_type = (words >> np.uint64(60)) & np.uint64(0xF)
        cd = (
            (event_type == np.uint64(0))
            | (event_type == np.uint64(1))
            | (event_type == np.uint64(4))
            | (event_type == np.uint64(5))
        )
        if not np.any(cd):
            return 0

        cd_words = words[cd]
        cd_type = event_type[cd]
        x_base = ((cd_words >> np.uint64(43)) & np.uint64(0x7FF)).astype(np.int32)
        y_base = ((cd_words >> np.uint64(32)) & np.uint64(0x7FF)).astype(np.int32)
        vx = (cd_words & np.uint64(0xFFFFFFFF)).astype(np.uint32)
        valid = (x_base >= 0) & (x_base < WIDTH) & (y_base >= 0) & (y_base < HEIGHT) & (vx != 0)
        if not np.any(valid):
            return 0

        x_base = x_base[valid]
        y_base = y_base[valid]
        vx = vx[valid]
        cd_type = cd_type[valid]

        xs = []
        ys = []
        pols = []
        for bit in range(32):
            bit_mask = ((vx >> np.uint32(bit)) & np.uint32(1)) != 0
            if not np.any(bit_mask):
                continue
            xs.append(x_base[bit_mask] + bit)
            ys.append(y_base[bit_mask])
            pols.append(cd_type[bit_mask])
        if not xs:
            return 0

        x = np.concatenate(xs)
        y = np.concatenate(ys)
        pol = np.concatenate(pols)
        valid_xy = (x >= 0) & (x < WIDTH) & (y >= 0) & (y < HEIGHT)
        if not np.any(valid_xy):
            return 0

        x = x[valid_xy]
        y = y[valid_xy]
        pol = pol[valid_xy]

        x = ((x * VIEW_W) // WIDTH).clip(0, VIEW_W - 1)
        y = ((y * VIEW_H) // HEIGHT).clip(0, VIEW_H - 1)
        off = (pol == 0) | (pol == 4)
        on = ~off
        if self.polarity_mode == "ON":
            off[:] = False
        elif self.polarity_mode == "OFF":
            on[:] = False

        radius = max(0, min(4, int(self.point_radius)))
        if radius == 0:
            if np.any(off):
                self.display[y[off], x[off]] = self.off_color
            if np.any(on):
                self.display[y[on], x[on]] = self.on_color
        else:
            for dy in range(-radius, radius + 1):
                yy = (y + dy).clip(0, VIEW_H - 1)
                for dx in range(-radius, radius + 1):
                    xx = (x + dx).clip(0, VIEW_W - 1)
                    if np.any(off):
                        self.display[yy[off], xx[off]] = self.off_color
                    if np.any(on):
                        self.display[yy[on], xx[on]] = self.on_color
        return int(len(x))


class PSE2RecordingPlayer:
    def __init__(self, path, renderer, on_frame, on_status):
        self.path = path
        self.renderer = renderer
        self.on_frame = on_frame
        self.on_status = on_status
        self.stop_event = threading.Event()
        self.pause_event = threading.Event()
        self.thread = None
        self.decoder = EVT21Decoder()
        self.total_events = 0
        self.rate_mev_s = 0.0
        self.file_size = 0
        self.playback_clock_us = 0

    def start(self):
        self.stop_event.clear()
        self.pause_event.clear()
        self.renderer.reset()
        self.decoder.reset()
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def stop(self):
        self.stop_event.set()
        self.pause_event.clear()
        if self.thread:
            self.thread.join(timeout=3.0)

    def is_recording(self):
        return False

    def set_paused(self, paused):
        if paused:
            self.pause_event.set()
        else:
            self.pause_event.clear()

    def is_paused(self):
        return self.pause_event.is_set()

    def _skip_metavision_header(self, file_obj):
        first = file_obj.peek(1)[:1] if hasattr(file_obj, "peek") else file_obj.read(1)
        if not hasattr(file_obj, "peek"):
            file_obj.seek(0)
        if first != b"%":
            return
        while True:
            line = file_obj.readline()
            if not line or line.strip() == b"% end":
                break

    def _run(self):
        try:
            self.file_size = os.path.getsize(self.path)
            with open(self.path, "rb", buffering=1024 * 1024) as file_obj:
                self._skip_metavision_header(file_obj)
                self.on_status("Playback open: %s" % self.path)
                chunk_size = 64 * 1024
                last_frame_time = 0.0
                last_rate_time = time.monotonic()
                last_rate_events = 0
                last_batch_ts = None
                while not self.stop_event.is_set():
                    while self.pause_event.is_set() and not self.stop_event.is_set():
                        self.on_frame(self.renderer.render_frame("Playback", self.rate_mev_s, False, True))
                        time.sleep(0.1)
                    payload = file_obj.read(chunk_size)
                    if not payload:
                        break

                    batch = self.decoder.decode(payload)
                    if batch.count:
                        preview_batch = self._prepare_preview_batch(batch)
                        self.renderer.add_batch(preview_batch)
                        self.total_events += batch.count

                    now = time.monotonic()
                    settings = self.renderer.snapshot_settings()
                    if now - last_frame_time >= 1.0 / max(1, settings["fps"]):
                        last_frame_time = now
                        self.on_frame(self.renderer.render_frame("Playback", self.rate_mev_s, False, False))

                    if batch.count and last_batch_ts is not None:
                        delta_us = max(0, preview_batch.t_max - last_batch_ts)
                        sleep_s = min(0.04, delta_us / 1_000_000.0)
                        if sleep_s > 0:
                            time.sleep(sleep_s)
                    if batch.count:
                        last_batch_ts = preview_batch.t_max

                    if now - last_rate_time >= 1.0:
                        delta_events = self.total_events - last_rate_events
                        last_rate_events = self.total_events
                        last_rate_time = now
                        self.rate_mev_s = delta_events / 1_000_000.0
                        pct = 0.0 if self.file_size <= 0 else (file_obj.tell() / self.file_size) * 100.0
                        self.on_status("Playback: %.1f%%, %.2f Mev/s, events=%s" % (pct, self.rate_mev_s, self.total_events))

                self.on_frame(self.renderer.render_frame("Playback", self.rate_mev_s, False, False))
                self.on_status("Playback finished: %s events from %s" % (self.total_events, self.path))
        except Exception as exc:
            self.on_status("Playback failed: %s" % exc)

    def _prepare_preview_batch(self, batch):
        settings = self.renderer.snapshot_settings()
        frame_period_us = int(1_000_000 / max(1, settings["fps"]))
        span = max(0, batch.t_max - batch.t_min)
        long_span = max(settings["accumulation_us"] * 4, 100000)
        if span <= long_span:
            if self.playback_clock_us == 0:
                self.playback_clock_us = batch.t_min
            return batch

        display_span = max(1000, settings["accumulation_us"])
        local_ts = batch.timestamp - batch.t_min
        scaled_ts = ((local_ts.astype(np.int64) * display_span) // max(1, span)) + self.playback_clock_us
        self.playback_clock_us += max(frame_period_us, display_span)
        return EventBatch(batch.x, batch.y, batch.polarity, scaled_ts.astype(np.int64, copy=False))


class BiasController:
    line_re = re.compile(
        r"(?P<name>bias_[a-z_]+)\s+0x[0-9a-fA-F]+\s+\(int\)\s+:\s+"
        r"min=(?P<min>-?\d+)\s+max=(?P<max>-?\d+)\s+step=(?P<step>-?\d+)\s+"
        r"default=(?P<default>-?\d+)\s+value=(?P<value>-?\d+)"
    )

    def __init__(self, device=DEFAULT_BIAS_DEVICE):
        self.device = device

    def read_controls(self):
        result = subprocess.run(
            ["v4l2-ctl", "-d", self.device, "--list-ctrls-menus"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            raise RuntimeError(result.stdout.strip() or "v4l2-ctl failed")
        controls = {}
        for line in result.stdout.splitlines():
            match = self.line_re.search(line)
            if not match:
                continue
            data = match.groupdict()
            name = data["name"]
            controls[name] = {
                "name": name,
                "min": int(data["min"]),
                "max": int(data["max"]),
                "step": max(1, abs(int(data["step"]))),
                "default": int(data["default"]),
                "value": int(data["value"]),
                "help": BIAS_HELP.get(name, ""),
            }
        return controls

    def set_control(self, name, value):
        result = subprocess.run(
            ["v4l2-ctl", "-d", self.device, "--set-ctrl", "%s=%s" % (name, int(value))],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            raise RuntimeError(result.stdout.strip() or "Could not set %s" % name)


class EventCameraApp(Gtk.Window):
    def __init__(self):
        super().__init__(title="KV260 Event Camera")
        self.set_default_size(1220, 850)
        self.connect("destroy", self.on_destroy)
        self.renderer = EventFrameRenderer()
        self.source = None
        self.source_mode = "Idle"
        self.latest_frame = np.zeros((VIEW_H, VIEW_W, 3), dtype=np.uint8)
        self.frame_lock = threading.Lock()
        self.pixbuf_data = None
        self.recording = False
        self.playback_paused = False
        self.status_text = "Ready."
        self.command_server = None
        self.bias_controller = BiasController()
        self.bias_widgets = {}
        self.bias_controls = {}

        self.install_css()
        self.build_ui()
        self.set_status("Ready. Open Live owns /dev/video0 directly; Close releases it.")
        GLib.timeout_add(33, self.refresh_image)
        GLib.timeout_add(500, self.refresh_recording_status)
        self.start_command_server()
        self.refresh_bias_controls_async()
        if os.environ.get("KV260_EVENT_APP_AUTO_OPEN", "1") != "0":
            GLib.timeout_add(500, self.auto_open_camera)

    def install_css(self):
        provider = Gtk.CssProvider()
        provider.load_from_data(
            b"""
            window { background: #f4f6fb; }
            .title { color: #111827; font-size: 22px; font-weight: 700; }
            .subtitle { color: #526070; }
            .section { background: #ffffff; border: 1px solid #d9e0ea; border-radius: 8px; padding: 8px; }
            .primary { background: #2563eb; color: #ffffff; font-weight: 700; }
            .success { background: #059669; color: #ffffff; font-weight: 700; }
            .danger { background: #dc2626; color: #ffffff; font-weight: 700; }
            .warn { background: #d97706; color: #ffffff; font-weight: 700; }
            .neutral { background: #475569; color: #ffffff; font-weight: 700; }
            button:disabled { background: #cbd5e1; color: #64748b; }
            .status { color: #1f2937; }
            """
        )
        screen = Gdk.Screen.get_default()
        if screen:
            Gtk.StyleContext.add_provider_for_screen(screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    def build_ui(self):
        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        root.set_border_width(10)
        self.add(root)

        title = Gtk.Label(label="KV260 Event Camera")
        title.set_xalign(0)
        title.get_style_context().add_class("title")
        root.pack_start(title, False, False, 0)

        subtitle = Gtk.Label(label="Live PSE2 preview, raw recording, playback, display tuning, and IMX636 bias controls.")
        subtitle.set_xalign(0)
        subtitle.get_style_context().add_class("subtitle")
        root.pack_start(subtitle, False, False, 0)

        self.notebook = Gtk.Notebook()
        self.notebook.set_size_request(-1, 258)
        root.pack_start(self.notebook, False, False, 0)
        self.notebook.append_page(self.build_camera_tab(), Gtk.Label(label="Camera"))
        self.notebook.append_page(self.build_display_tab(), Gtk.Label(label="Display"))
        self.notebook.append_page(self.build_bias_tab(), Gtk.Label(label="Biases"))

        preview_frame = Gtk.Frame(label="Event Preview")
        preview_frame.get_style_context().add_class("section")
        self.image = Gtk.Image()
        self.image.set_size_request(VIEW_W, VIEW_H)
        preview_frame.add(self.image)
        root.pack_start(preview_frame, True, True, 0)

        self.status = Gtk.Label(label=self.status_text)
        self.status.set_xalign(0)
        self.status.set_line_wrap(True)
        self.status.set_max_width_chars(160)
        self.status.get_style_context().add_class("status")
        root.pack_start(self.status, False, False, 0)

    def make_button(self, label, style, callback):
        button = Gtk.Button(label=label)
        button.connect("clicked", callback)
        button.get_style_context().add_class(style)
        return button

    def build_camera_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_border_width(8)

        buttons = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        box.pack_start(buttons, False, False, 0)
        self.open_button = self.make_button("Open Live", "primary", self.on_open_camera)
        self.close_button = self.make_button("Close", "danger", self.on_close_camera)
        self.record_button = self.make_button("Start Recording", "success", self.on_record)
        self.open_recording_button = self.make_button("Open Recording", "primary", self.on_open_recording)
        self.pause_button = self.make_button("Pause", "neutral", self.on_pause_playback)
        self.new_button = self.make_button("New Name", "neutral", self.on_new_name)
        self.recover_button = self.make_button("Recover Stack", "warn", self.on_recover)
        self.quit_button = self.make_button("Quit", "danger", lambda _button: self.close())
        for button in (
            self.open_button,
            self.close_button,
            self.record_button,
            self.open_recording_button,
            self.pause_button,
            self.new_button,
            self.recover_button,
            self.quit_button,
        ):
            buttons.pack_start(button, False, False, 0)

        grid = Gtk.Grid(column_spacing=8, row_spacing=6)
        box.pack_start(grid, False, False, 0)

        grid.attach(Gtk.Label(label="Record folder"), 0, 0, 1, 1)
        self.folder_entry = Gtk.Entry()
        self.folder_entry.set_text(DEFAULT_RECORD_DIR)
        self.folder_entry.set_hexpand(True)
        grid.attach(self.folder_entry, 1, 0, 5, 1)
        browse = self.make_button("Browse", "neutral", self.on_browse_folder)
        grid.attach(browse, 6, 0, 1, 1)

        grid.attach(Gtk.Label(label="File name"), 0, 1, 1, 1)
        self.file_entry = Gtk.Entry()
        self.file_entry.set_text(self.default_filename())
        self.file_entry.set_hexpand(True)
        grid.attach(self.file_entry, 1, 1, 3, 1)

        grid.attach(Gtk.Label(label="Video node"), 4, 1, 1, 1)
        self.device_entry = Gtk.Entry()
        self.device_entry.set_text(DEFAULT_DEVICE)
        grid.attach(self.device_entry, 5, 1, 2, 1)

        self.mode_label = Gtk.Label(label="Mode: Idle")
        self.mode_label.set_xalign(0)
        box.pack_start(self.mode_label, False, False, 0)

        record_status_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self.priority_check = Gtk.CheckButton(label="Recording Priority")
        self.priority_check.set_active(True)
        self.priority_check.connect("toggled", self.on_recording_priority_changed)
        record_status_row.pack_start(self.priority_check, False, False, 0)
        self.record_status_label = Gtk.Label(label="Recording: idle")
        self.record_status_label.set_xalign(0)
        self.record_status_label.set_hexpand(True)
        self.record_status_label.set_line_wrap(True)
        self.record_status_label.set_max_width_chars(96)
        record_status_row.pack_start(self.record_status_label, True, True, 0)
        box.pack_start(record_status_row, False, False, 0)

        self.update_controls()
        return box

    def build_display_tab(self):
        grid = Gtk.Grid(column_spacing=10, row_spacing=8)
        grid.set_border_width(8)

        grid.attach(Gtk.Label(label="Playback accumulation ms"), 0, 0, 1, 1)
        self.accum_spin = Gtk.SpinButton.new_with_range(1, 200, 1)
        self.accum_spin.set_value(10)
        self.accum_spin.connect("value-changed", self.on_render_setting_changed)
        grid.attach(self.accum_spin, 1, 0, 1, 1)

        grid.attach(Gtk.Label(label="FPS"), 2, 0, 1, 1)
        self.fps_spin = Gtk.SpinButton.new_with_range(5, 60, 1)
        self.fps_spin.set_value(30)
        self.fps_spin.connect("value-changed", self.on_render_setting_changed)
        grid.attach(self.fps_spin, 3, 0, 1, 1)

        grid.attach(Gtk.Label(label="Palette"), 4, 0, 1, 1)
        self.palette_combo = Gtk.ComboBoxText()
        for name in PALETTES:
            self.palette_combo.append_text(name)
        self.palette_combo.set_active(0)
        self.palette_combo.connect("changed", self.on_render_setting_changed)
        grid.attach(self.palette_combo, 5, 0, 1, 1)

        grid.attach(Gtk.Label(label="Polarity"), 0, 1, 1, 1)
        self.polarity_combo = Gtk.ComboBoxText()
        for name in ("All", "ON", "OFF"):
            self.polarity_combo.append_text(name)
        self.polarity_combo.set_active(0)
        self.polarity_combo.connect("changed", self.on_render_setting_changed)
        grid.attach(self.polarity_combo, 1, 1, 1, 1)

        grid.attach(Gtk.Label(label="Point radius"), 2, 1, 1, 1)
        self.radius_spin = Gtk.SpinButton.new_with_range(0, 4, 1)
        self.radius_spin.set_value(1)
        self.radius_spin.connect("value-changed", self.on_render_setting_changed)
        grid.attach(self.radius_spin, 3, 1, 1, 1)

        grid.attach(Gtk.Label(label="Event trail"), 4, 1, 1, 1)
        self.trail_scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0.50, 0.995, 0.005)
        self.trail_scale.set_digits(3)
        self.trail_scale.set_value(0.82)
        self.trail_scale.set_hexpand(True)
        self.trail_scale.connect("value-changed", self.on_render_setting_changed)
        grid.attach(self.trail_scale, 5, 1, 2, 1)

        self.osd_check = Gtk.CheckButton(label="Playback OSD overlay")
        self.osd_check.set_active(True)
        self.osd_check.connect("toggled", self.on_render_setting_changed)
        grid.attach(self.osd_check, 0, 2, 2, 1)

        hint = Gtk.Label(
            label="Live preview uses immediate draw-and-decay for responsiveness. Accumulation controls recording playback; use polarity and trail to inspect event balance."
        )
        hint.set_xalign(0)
        hint.set_line_wrap(True)
        grid.attach(hint, 0, 3, 7, 1)
        self.on_render_setting_changed(None)
        return grid

    def build_bias_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_border_width(8)
        controls = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        box.pack_start(controls, False, False, 0)
        for label, style, callback in (
            ("Refresh Biases", "neutral", self.on_refresh_biases),
            ("Apply All", "primary", self.on_apply_biases),
            ("Reset Defaults", "warn", self.on_reset_biases),
            ("Save Preset", "success", self.on_save_bias_preset),
            ("Load Preset", "primary", self.on_load_bias_preset),
        ):
            controls.pack_start(self.make_button(label, style, callback), False, False, 0)

        self.bias_grid = Gtk.Grid(column_spacing=8, row_spacing=6)
        self.bias_grid.set_hexpand(True)
        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scroller.add(self.bias_grid)
        box.pack_start(scroller, True, True, 0)

        self.bias_note = Gtk.Label(label="Bias controls are read from /dev/v4l-subdev3. Refresh after camera stack reloads.")
        self.bias_note.set_xalign(0)
        self.bias_note.set_line_wrap(True)
        box.pack_start(self.bias_note, False, False, 0)
        return box

    @staticmethod
    def default_filename():
        return "event_%s.pse2.raw" % datetime.now().strftime("%Y%m%d_%H%M%S")

    def set_status(self, message):
        print(str(message), flush=True)
        GLib.idle_add(self._set_status_main, str(message))

    def _set_status_main(self, message):
        self.status_text = message
        self.status.set_text(message)
        return False

    def start_command_server(self):
        try:
            os.unlink(APP_SOCKET_PATH)
        except FileNotFoundError:
            pass
        except OSError:
            pass
        self.command_server = AppCommandServer(self)
        self.command_server.start()

    def present_from_launcher(self):
        self.show_all()
        self.present()
        self.set_keep_above(True)

        def unset_keep_above():
            self.set_keep_above(False)
            return False

        GLib.timeout_add(350, unset_keep_above)
        return False

    def on_frame(self, frame):
        with self.frame_lock:
            self.latest_frame = frame

    def refresh_image(self):
        with self.frame_lock:
            frame = self.latest_frame.copy()
        if frame.size:
            data = frame.tobytes()
            self.pixbuf_data = data
            pixbuf = GdkPixbuf.Pixbuf.new_from_data(
                data,
                GdkPixbuf.Colorspace.RGB,
                False,
                8,
                frame.shape[1],
                frame.shape[0],
                frame.shape[1] * 3,
                None,
                None,
            )
            self.image.set_from_pixbuf(pixbuf)
        return True

    def refresh_recording_status(self):
        if not hasattr(self, "record_status_label"):
            return True
        text = "Recording: idle"
        if isinstance(self.source, V4L2EventStream) and self.source.is_recording():
            stats = self.source.recording_snapshot()
            if stats:
                mb = stats["bytes_written"] / (1024.0 * 1024.0)
                text = (
                    "Recording: %.1f MB, %s buffers, queue %s/%s, drops %s"
                    % (
                        mb,
                        stats["buffers_written"],
                        stats["pending_buffers"],
                        stats["queue_size"],
                        stats["dropped_buffers"],
                    )
                )
                if stats["preview_skipped_buffers"]:
                    text += ", preview skipped %s" % stats["preview_skipped_buffers"]
                if stats["write_error"]:
                    text += ", write error"
        self.record_status_label.set_text(text)
        return True

    def update_controls(self):
        live = isinstance(self.source, V4L2EventStream)
        playback = isinstance(self.source, PSE2RecordingPlayer)
        self.open_button.set_sensitive(self.source is None)
        self.close_button.set_sensitive(self.source is not None)
        self.record_button.set_sensitive(live)
        self.open_recording_button.set_sensitive(True)
        self.pause_button.set_sensitive(playback)
        self.pause_button.set_label("Resume" if self.playback_paused else "Pause")
        self.record_button.set_label("Stop Recording" if self.recording else "Start Recording")
        self.mode_label.set_text("Mode: %s" % self.source_mode)
        self.refresh_recording_status()

    def output_path(self):
        folder = os.path.abspath(os.path.expanduser(self.folder_entry.get_text().strip() or DEFAULT_RECORD_DIR))
        name = self.file_entry.get_text().strip() or self.default_filename()
        if not name.endswith(".raw"):
            name += ".raw"
        return os.path.join(folder, name)

    def on_new_name(self, _button):
        self.file_entry.set_text(self.default_filename())

    def on_browse_folder(self, _button):
        dialog = Gtk.FileChooserDialog(
            title="Select recording folder",
            parent=self,
            action=Gtk.FileChooserAction.SELECT_FOLDER,
            buttons=(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, Gtk.STOCK_OPEN, Gtk.ResponseType.OK),
        )
        dialog.set_filename(os.path.abspath(os.path.expanduser(self.folder_entry.get_text())))
        if dialog.run() == Gtk.ResponseType.OK:
            self.folder_entry.set_text(dialog.get_filename())
        dialog.destroy()

    def on_open_recording(self, _button):
        dialog = Gtk.FileChooserDialog(
            title="Open PSE2/EVT2.1 recording",
            parent=self,
            action=Gtk.FileChooserAction.OPEN,
            buttons=(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, Gtk.STOCK_OPEN, Gtk.ResponseType.OK),
        )
        dialog.set_current_folder(os.path.abspath(os.path.expanduser(self.folder_entry.get_text() or DEFAULT_RECORD_DIR)))
        filter_raw = Gtk.FileFilter()
        filter_raw.set_name("PSE2/RAW recordings")
        filter_raw.add_pattern("*.raw")
        filter_raw.add_pattern("*.pse2")
        dialog.add_filter(filter_raw)
        if dialog.run() == Gtk.ResponseType.OK:
            path = dialog.get_filename()
            dialog.destroy()
            self.open_recording(path)
            return
        dialog.destroy()

    def open_recording(self, path):
        self.close_stream()
        self.source = PSE2RecordingPlayer(path, self.renderer, self.on_frame, self.set_status)
        self.source_mode = "Playback"
        self.playback_paused = False
        self.source.start()
        self.update_controls()

    def auto_open_camera(self):
        if not self.source:
            self.on_open_camera(self.open_button)
        return False

    def on_render_setting_changed(self, _widget):
        palette = self.palette_combo.get_active_text() if hasattr(self, "palette_combo") else "Dark"
        polarity = self.polarity_combo.get_active_text() if hasattr(self, "polarity_combo") else "All"
        self.renderer.configure(
            accumulation_ms=self.accum_spin.get_value() if hasattr(self, "accum_spin") else 10,
            fps=self.fps_spin.get_value() if hasattr(self, "fps_spin") else 30,
            palette=palette,
            polarity=polarity,
            point_radius=self.radius_spin.get_value() if hasattr(self, "radius_spin") else 1,
            trail=self.trail_scale.get_value() if hasattr(self, "trail_scale") else 0.82,
            osd=self.osd_check.get_active() if hasattr(self, "osd_check") else True,
        )
        if isinstance(self.source, V4L2EventStream):
            self.source.apply_render_settings(self.renderer.snapshot_settings())

    def on_recording_priority_changed(self, _widget):
        if isinstance(self.source, V4L2EventStream):
            self.source.set_recording_priority(self.priority_check.get_active())
        self.refresh_recording_status()

    def on_open_camera(self, _button):
        if self.source:
            self.set_status("A source is already open. Close it first.")
            return
        self.stop_native_viewer()
        device = self.device_entry.get_text().strip() or DEFAULT_DEVICE
        self.source = V4L2EventStream(device, self.renderer, self.on_frame, self.set_status)
        self.source.apply_render_settings(self.renderer.snapshot_settings())
        self.source.set_recording_priority(self.priority_check.get_active())
        self.source_mode = "Live"
        self.source.start()
        self.update_controls()

    def on_close_camera(self, _button):
        self.close_stream()

    def close_stream(self):
        if self.source:
            self.source.stop()
            self.source = None
        self.recording = False
        self.playback_paused = False
        self.source_mode = "Idle"
        self.update_controls()

    def on_record(self, _button):
        if not isinstance(self.source, V4L2EventStream):
            self.set_status("Open Live before recording.")
            return
        if self.recording:
            self.source.stop_recording()
            self.recording = False
            self.update_controls()
            return
        self.start_recording()

    def start_recording(self):
        try:
            path = self.output_path()
            self.source.start_recording(path)
            self.recording = True
            self.update_controls()
        except Exception as exc:
            self.set_status("Could not start recording: %s" % exc)

    def on_pause_playback(self, _button):
        if not isinstance(self.source, PSE2RecordingPlayer):
            return
        self.playback_paused = not self.playback_paused
        self.source.set_paused(self.playback_paused)
        self.update_controls()

    def on_recover(self, _button):
        self.close_stream()
        self.set_status("Recovering camera stack...")

        def worker():
            cmd = [os.path.join(HERE, "kv260-launch-desktop-viewer.sh"), "--recover"]
            env = os.environ.copy()
            env.setdefault("DISPLAY", ":0")
            subprocess.run(cmd, cwd=PROJECT_DIR, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run([os.path.join(HERE, "kv260-event-visual-gui-local.sh"), "--stop", "--force"], cwd=PROJECT_DIR)
            self.set_status("Recovery complete. Click Open Live.")
            self.refresh_bias_controls_async()

        threading.Thread(target=worker, daemon=True).start()

    def stop_native_viewer(self):
        subprocess.run(
            [os.path.join(HERE, "kv260-event-visual-gui-local.sh"), "--stop", "--force"],
            cwd=PROJECT_DIR,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    def refresh_bias_controls_async(self):
        def worker():
            try:
                controls = self.bias_controller.read_controls()
                GLib.idle_add(self.build_bias_controls, controls)
            except Exception as exc:
                self.set_status("Could not read bias controls: %s" % exc)

        threading.Thread(target=worker, daemon=True).start()

    def build_bias_controls(self, controls):
        for child in self.bias_grid.get_children():
            self.bias_grid.remove(child)
        self.bias_widgets = {}
        self.bias_controls = controls
        headers = ("Bias", "Value", "Range", "Default", "Purpose")
        for col, header in enumerate(headers):
            label = Gtk.Label(label=header)
            label.set_xalign(0)
            self.bias_grid.attach(label, col, 0, 1, 1)
        row = 1
        for name in COMMON_BIASES:
            info = controls.get(name)
            if not info:
                continue
            self.bias_grid.attach(Gtk.Label(label=name), 0, row, 1, 1)
            adj = Gtk.Adjustment(value=info["value"], lower=info["min"], upper=info["max"], step_increment=info["step"])
            scale = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL, adjustment=adj)
            scale.set_digits(0)
            scale.set_hexpand(True)
            spin = Gtk.SpinButton(adjustment=adj, climb_rate=1, digits=0)
            self.bias_grid.attach(scale, 1, row, 1, 1)
            self.bias_grid.attach(spin, 2, row, 1, 1)
            self.bias_grid.attach(Gtk.Label(label="%s..%s" % (info["min"], info["max"])), 3, row, 1, 1)
            self.bias_grid.attach(Gtk.Label(label=str(info["default"])), 4, row, 1, 1)
            help_label = Gtk.Label(label=info["help"])
            help_label.set_xalign(0)
            help_label.set_line_wrap(True)
            self.bias_grid.attach(help_label, 5, row, 1, 1)
            self.bias_widgets[name] = {"scale": scale, "spin": spin, "info": info}
            row += 1
        if not self.bias_widgets:
            self.bias_grid.attach(Gtk.Label(label="No bias controls found on %s." % self.bias_controller.device), 0, 1, 5, 1)
        self.bias_grid.show_all()
        self.set_status("Bias controls refreshed from %s." % self.bias_controller.device)
        return False

    def on_refresh_biases(self, _button):
        self.refresh_bias_controls_async()

    def on_apply_biases(self, _button):
        values = {name: int(widget["spin"].get_value()) for name, widget in self.bias_widgets.items()}
        self.apply_bias_values(values, "Biases applied")

    def apply_bias_values(self, values, success_message):
        def worker():
            try:
                for name, value in values.items():
                    self.bias_controller.set_control(name, value)
                self.set_status("%s: %s" % (success_message, ", ".join("%s=%s" % item for item in values.items())))
                self.refresh_bias_controls_async()
            except Exception as exc:
                self.set_status("Bias update failed: %s" % exc)

        threading.Thread(target=worker, daemon=True).start()

    def on_reset_biases(self, _button):
        values = {name: widget["info"]["default"] for name, widget in self.bias_widgets.items()}
        self.apply_bias_values(values, "Bias defaults restored")

    def on_save_bias_preset(self, _button):
        path = os.path.join(os.path.abspath(os.path.expanduser(self.folder_entry.get_text() or DEFAULT_RECORD_DIR)), "biases_%s.json" % datetime.now().strftime("%Y%m%d_%H%M%S"))
        dialog = Gtk.FileChooserDialog(
            title="Save bias preset",
            parent=self,
            action=Gtk.FileChooserAction.SAVE,
            buttons=(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, Gtk.STOCK_SAVE, Gtk.ResponseType.OK),
        )
        dialog.set_filename(path)
        if dialog.run() == Gtk.ResponseType.OK:
            path = dialog.get_filename()
            data = {
                "created": datetime.now().isoformat(timespec="seconds"),
                "device": self.bias_controller.device,
                "biases": {name: int(widget["spin"].get_value()) for name, widget in self.bias_widgets.items()},
            }
            try:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "w", encoding="utf-8") as preset:
                    json.dump(data, preset, indent=2)
                    preset.write("\n")
                self.set_status("Bias preset saved: %s" % path)
            except Exception as exc:
                self.set_status("Could not save bias preset: %s" % exc)
        dialog.destroy()

    def on_load_bias_preset(self, _button):
        dialog = Gtk.FileChooserDialog(
            title="Load bias preset",
            parent=self,
            action=Gtk.FileChooserAction.OPEN,
            buttons=(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, Gtk.STOCK_OPEN, Gtk.ResponseType.OK),
        )
        dialog.set_current_folder(os.path.abspath(os.path.expanduser(self.folder_entry.get_text() or DEFAULT_RECORD_DIR)))
        filter_json = Gtk.FileFilter()
        filter_json.set_name("JSON presets")
        filter_json.add_pattern("*.json")
        dialog.add_filter(filter_json)
        if dialog.run() == Gtk.ResponseType.OK:
            path = dialog.get_filename()
            try:
                with open(path, "r", encoding="utf-8") as preset:
                    data = json.load(preset)
                values = data.get("biases", {})
                for name, value in values.items():
                    widget = self.bias_widgets.get(name)
                    if widget:
                        widget["spin"].set_value(int(value))
                self.apply_bias_values({name: int(value) for name, value in values.items() if name in self.bias_widgets}, "Bias preset loaded")
            except Exception as exc:
                self.set_status("Could not load bias preset: %s" % exc)
        dialog.destroy()

    def on_destroy(self, _widget):
        self.close_stream()
        if self.command_server:
            self.command_server.stop()
        Gtk.main_quit()


class AppCommandServer(threading.Thread):
    def __init__(self, app):
        super().__init__(daemon=True)
        self.app = app
        self.stop_event = threading.Event()
        self.sock = None

    def run(self):
        try:
            self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.sock.bind(APP_SOCKET_PATH)
            os.chmod(APP_SOCKET_PATH, 0o666)
            self.sock.listen(4)
            self.sock.settimeout(0.5)
            while not self.stop_event.is_set():
                try:
                    conn, _addr = self.sock.accept()
                except socket.timeout:
                    continue
                with conn:
                    command = conn.recv(64).decode("utf-8", "ignore").strip()
                    if command == "present":
                        GLib.idle_add(self.app.present_from_launcher)
                    elif command in ("quit", "close"):
                        GLib.idle_add(self.app.close)
        except Exception as exc:
            self.app.set_status("Launcher command socket failed: %s" % exc)
        finally:
            try:
                if self.sock:
                    self.sock.close()
            finally:
                try:
                    os.unlink(APP_SOCKET_PATH)
                except OSError:
                    pass

    def stop(self):
        self.stop_event.set()
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
                client.settimeout(0.2)
                client.connect(APP_SOCKET_PATH)
                client.sendall(b"stop")
        except OSError:
            pass


def main():
    os.environ.setdefault("DISPLAY", ":0")
    lock_file = open(APP_LOCK_PATH, "w", encoding="utf-8")
    try:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("KV260 Event Camera is already running.")
        return 0
    lock_file.write("%s\n" % os.getpid())
    lock_file.flush()

    win = EventCameraApp()
    win.show_all()
    Gtk.main()
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
    lock_file.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
