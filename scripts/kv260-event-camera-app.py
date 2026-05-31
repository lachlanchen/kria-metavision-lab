#!/usr/bin/env python3
"""KV260 Prophesee event-camera app.

This app reads the PSE2/EVT2.1 V4L2 node directly, renders events with GTK,
and records the raw PSE2 byte stream with a JSON sidecar.
"""

import ctypes
import fcntl
import json
import mmap
import os
import select
import socket
import subprocess
import threading
import time
from datetime import datetime

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf, GLib, Gtk

import numpy as np


HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(HERE)
DEFAULT_DEVICE = "/dev/video0"
WIDTH = 1280
HEIGHT = 720
VIEW_W = 960
VIEW_H = 540
DEFAULT_RECORD_DIR = os.path.expanduser(os.environ.get("KV260_EVENT_RECORD_DIR", "~/event_recordings"))
APP_LOCK_PATH = "/tmp/kv260-event-camera-app.lock"
APP_SOCKET_PATH = "/tmp/kv260-event-camera-app.sock"


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


class V4L2EventStream:
    def __init__(self, device, on_frame, on_status):
        self.device = device
        self.on_frame = on_frame
        self.on_status = on_status
        self.stop_event = threading.Event()
        self.thread = None
        self.fd = None
        self.buffers = []
        self.display = np.zeros((VIEW_H, VIEW_W, 3), dtype=np.uint8)
        self.record_lock = threading.Lock()
        self.record_file = None
        self.record_path = None
        self.record_bytes = 0
        self.record_events = 0
        self.total_events = 0
        self.total_buffers = 0
        self.decay = 0.82
        self.point_radius = 1

    def start(self):
        self.stop_event.clear()
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def stop(self):
        self.stop_event.set()
        if self.thread:
            self.thread.join(timeout=3.0)
        self.stop_recording()

    def start_recording(self, path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        meta_path = path + ".json"
        metadata = {
            "created": datetime.now().isoformat(timespec="seconds"),
            "format": "PSEE_EVT21",
            "pixel_format": "PSE2",
            "width": WIDTH,
            "height": HEIGHT,
            "device": self.device,
            "note": "Raw V4L2 PSE2/EVT2.1 byte stream captured directly from the KV260 event node.",
        }
        with self.record_lock:
            self.stop_recording_locked()
            self.record_file = open(path, "wb", buffering=1024 * 1024)
            with open(meta_path, "w", encoding="utf-8") as meta_file:
                json.dump(metadata, meta_file, indent=2)
                meta_file.write("\n")
            self.record_path = path
            self.record_bytes = 0
            self.record_events = 0
        self.on_status("Recording raw PSE2 stream to %s" % path)

    def stop_recording(self):
        with self.record_lock:
            self.stop_recording_locked()

    def stop_recording_locked(self):
        if self.record_file:
            path = self.record_path
            bytes_written = self.record_bytes
            events_written = self.record_events
            self.record_file.flush()
            self.record_file.close()
            self.record_file = None
            self.record_path = None
            self.on_status("Recording stopped: %s bytes, %s events -> %s" % (bytes_written, events_written, path))

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
            self.on_status("Camera stream open: %s (%sx%s PSE2)" % (self.device, WIDTH, HEIGHT))
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

                payload = self.buffers[buf.index][: buf.bytesused]
                events = self._decode_and_draw(payload)
                self.total_events += events
                self.total_buffers += 1

                with self.record_lock:
                    if self.record_file:
                        self.record_file.write(payload)
                        self.record_bytes += len(payload)
                        self.record_events += events

                now = time.monotonic()
                if now - last_frame_time > 0.033:
                    last_frame_time = now
                    self.on_frame(self.display.copy())
                    self.display[:] = (self.display.astype(np.float32) * self.decay).astype(np.uint8)
                if now - last_rate_time > 1.0:
                    delta_events = self.total_events - last_rate_events
                    last_rate_events = self.total_events
                    last_rate_time = now
                    rec = " recording" if self.record_file else ""
                    self.on_status("Live: %.2f Mev/s, buffers=%s%s" % (delta_events / 1_000_000.0, self.total_buffers, rec))

                fcntl.ioctl(self.fd, VIDIOC_QBUF, buf)
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
        # EVT2.1/PSE2 is a 64-bit event-vector format:
        # bits 63..60 type, 59..54 timestamp low, 53..43 x group,
        # 42..32 y, 31..0 vx bitmask. x is aligned to a 32-pixel group;
        # each set vx bit expands to one event at x + bit_index.
        words = np.frombuffer(payload[:usable], dtype="<u8")
        event_type = (words >> np.uint64(60)) & np.uint64(0xF)
        cd = (event_type == 0) | (event_type == 1) | (event_type == 4) | (event_type == 5)
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
        valid_xy = (x >= 0) & (x < WIDTH)
        if not np.any(valid_xy):
            return 0
        x = x[valid_xy]
        y = y[valid_xy]
        pol = pol[valid_xy]
        x = ((x * VIEW_W) // WIDTH).clip(0, VIEW_W - 1)
        y = ((y * VIEW_H) // HEIGHT).clip(0, VIEW_H - 1)
        off = (pol == 0) | (pol == 4)
        on = ~off
        radius = max(0, min(4, int(self.point_radius)))
        if radius == 0:
            if np.any(off):
                self.display[y[off], x[off]] = (230, 80, 60)
            if np.any(on):
                self.display[y[on], x[on]] = (60, 210, 130)
        else:
            for dy in range(-radius, radius + 1):
                yy = (y + dy).clip(0, VIEW_H - 1)
                for dx in range(-radius, radius + 1):
                    xx = (x + dx).clip(0, VIEW_W - 1)
                    if np.any(off):
                        self.display[yy[off], xx[off]] = (230, 80, 60)
                    if np.any(on):
                        self.display[yy[on], xx[on]] = (60, 210, 130)
        return int(len(x))


class EventCameraApp(Gtk.Window):
    def __init__(self):
        super().__init__(title="KV260 Event Camera")
        self.set_default_size(1180, 760)
        self.connect("destroy", self.on_destroy)
        self.stream = None
        self.latest_frame = np.zeros((VIEW_H, VIEW_W, 3), dtype=np.uint8)
        self.frame_lock = threading.Lock()
        self.pixbuf_data = None
        self.recording = False
        self.status_text = "Ready."
        self.command_server = None

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        root.set_border_width(8)
        self.add(root)

        controls = Gtk.Grid(column_spacing=8, row_spacing=6)
        root.pack_start(controls, False, False, 0)

        self.open_button = Gtk.Button(label="Open Camera")
        self.open_button.connect("clicked", self.on_open_camera)
        controls.attach(self.open_button, 0, 0, 1, 1)

        self.close_button = Gtk.Button(label="Close Camera")
        self.close_button.connect("clicked", self.on_close_camera)
        controls.attach(self.close_button, 1, 0, 1, 1)

        self.record_button = Gtk.Button(label="Start Recording")
        self.record_button.connect("clicked", self.on_record)
        controls.attach(self.record_button, 2, 0, 1, 1)

        self.new_button = Gtk.Button(label="New Name")
        self.new_button.connect("clicked", self.on_new_name)
        controls.attach(self.new_button, 3, 0, 1, 1)

        self.recover_button = Gtk.Button(label="Recover Stack")
        self.recover_button.connect("clicked", self.on_recover)
        controls.attach(self.recover_button, 4, 0, 1, 1)

        self.quit_button = Gtk.Button(label="Quit")
        self.quit_button.connect("clicked", lambda _button: self.close())
        controls.attach(self.quit_button, 5, 0, 1, 1)

        controls.attach(Gtk.Label(label="Folder"), 0, 1, 1, 1)
        self.folder_entry = Gtk.Entry()
        self.folder_entry.set_text(DEFAULT_RECORD_DIR)
        self.folder_entry.set_hexpand(True)
        controls.attach(self.folder_entry, 1, 1, 4, 1)

        browse = Gtk.Button(label="Browse")
        browse.connect("clicked", self.on_browse)
        controls.attach(browse, 5, 1, 1, 1)

        controls.attach(Gtk.Label(label="File"), 0, 2, 1, 1)
        self.file_entry = Gtk.Entry()
        self.file_entry.set_text(self.default_filename())
        self.file_entry.set_hexpand(True)
        controls.attach(self.file_entry, 1, 2, 3, 1)

        controls.attach(Gtk.Label(label="Device"), 4, 2, 1, 1)
        self.device_entry = Gtk.Entry()
        self.device_entry.set_text(DEFAULT_DEVICE)
        controls.attach(self.device_entry, 5, 2, 1, 1)

        controls.attach(Gtk.Label(label="Persistence"), 0, 3, 1, 1)
        self.decay_scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0.50, 0.98, 0.01)
        self.decay_scale.set_value(0.82)
        self.decay_scale.set_hexpand(True)
        self.decay_scale.connect("value-changed", self.on_render_setting_changed)
        controls.attach(self.decay_scale, 1, 3, 2, 1)

        controls.attach(Gtk.Label(label="Point Radius"), 3, 3, 1, 1)
        self.radius_spin = Gtk.SpinButton.new_with_range(0, 4, 1)
        self.radius_spin.set_value(1)
        self.radius_spin.connect("value-changed", self.on_render_setting_changed)
        controls.attach(self.radius_spin, 4, 3, 1, 1)

        self.image = Gtk.Image()
        self.image.set_size_request(VIEW_W, VIEW_H)
        event_box = Gtk.EventBox()
        event_box.add(self.image)
        root.pack_start(event_box, True, True, 0)

        self.status = Gtk.Label(label=self.status_text)
        self.status.set_xalign(0)
        root.pack_start(self.status, False, False, 0)

        self.set_status("Ready. Open Camera owns /dev/video0 directly; Close Camera releases it.")
        GLib.timeout_add(33, self.refresh_image)
        self.start_command_server()
        if os.environ.get("KV260_EVENT_APP_AUTO_OPEN", "1") != "0":
            GLib.timeout_add(500, self.auto_open_camera)

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

    def output_path(self):
        folder = os.path.abspath(os.path.expanduser(self.folder_entry.get_text().strip() or DEFAULT_RECORD_DIR))
        name = self.file_entry.get_text().strip() or self.default_filename()
        if not name.endswith(".raw"):
            name += ".raw"
        return os.path.join(folder, name)

    def on_new_name(self, _button):
        self.file_entry.set_text(self.default_filename())

    def on_browse(self, _button):
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

    def auto_open_camera(self):
        if not self.stream:
            self.on_open_camera(self.open_button)
        return False

    def on_render_setting_changed(self, _widget):
        if self.stream:
            self.stream.decay = float(self.decay_scale.get_value())
            self.stream.point_radius = int(self.radius_spin.get_value())

    def on_open_camera(self, _button):
        if self.stream:
            self.set_status("Camera already open.")
            return
        self.stop_native_viewer()
        device = self.device_entry.get_text().strip() or DEFAULT_DEVICE
        self.stream = V4L2EventStream(device, self.on_frame, self.set_status)
        self.stream.decay = float(self.decay_scale.get_value())
        self.stream.point_radius = int(self.radius_spin.get_value())
        self.stream.start()
        self.open_button.set_sensitive(False)
        self.close_button.set_sensitive(True)

    def on_close_camera(self, _button):
        self.close_stream()

    def close_stream(self):
        if self.stream:
            self.stream.stop()
            self.stream = None
        self.recording = False
        self.record_button.set_label("Start Recording")
        self.open_button.set_sensitive(True)
        self.close_button.set_sensitive(True)

    def on_record(self, _button):
        if not self.stream:
            self.on_open_camera(_button)
            GLib.timeout_add(700, self._start_record_after_open)
            return
        if self.recording:
            self.stream.stop_recording()
            self.recording = False
            self.record_button.set_label("Start Recording")
            return
        self.start_recording()

    def _start_record_after_open(self):
        if self.stream:
            self.start_recording()
        return False

    def start_recording(self):
        try:
            path = self.output_path()
            self.stream.start_recording(path)
            self.recording = True
            self.record_button.set_label("Stop Recording")
        except Exception as exc:
            self.set_status("Could not start recording: %s" % exc)

    def on_recover(self, _button):
        self.close_stream()
        self.set_status("Recovering camera stack...")

        def worker():
            cmd = [os.path.join(HERE, "kv260-launch-desktop-viewer.sh"), "--recover"]
            env = os.environ.copy()
            env.setdefault("DISPLAY", ":0")
            subprocess.run(cmd, cwd=PROJECT_DIR, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run([os.path.join(HERE, "kv260-event-visual-gui-local.sh"), "--stop", "--force"], cwd=PROJECT_DIR)
            self.set_status("Recovery complete. Click Open Camera.")

        threading.Thread(target=worker, daemon=True).start()

    def stop_native_viewer(self):
        subprocess.run(
            [os.path.join(HERE, "kv260-event-visual-gui-local.sh"), "--stop", "--force"],
            cwd=PROJECT_DIR,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

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
