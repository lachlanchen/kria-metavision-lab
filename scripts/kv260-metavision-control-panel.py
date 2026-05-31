#!/usr/bin/env python3
"""Small X11 control panel for the KV260 Prophesee Metavision viewer."""

import ctypes
import os
import shlex
import subprocess
import sys
import threading
import time
from datetime import datetime


HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(HERE)
VIEWER_HELPER = os.path.join(HERE, "kv260-event-visual-gui-local.sh")
DESKTOP_HELPER = os.path.join(HERE, "kv260-launch-desktop-viewer.sh")
DEFAULT_RECORD_DIR = os.path.expanduser(os.environ.get("KV260_EVENT_RECORD_DIR", "~/event_recordings"))


KeyPress = 2
ButtonPress = 4
Expose = 12
ClientMessage = 33

KeyPressMask = 1 << 0
ButtonPressMask = 1 << 2
ExposureMask = 1 << 15
StructureNotifyMask = 1 << 17

XK_BackSpace = 0xFF08
XK_Tab = 0xFF09
XK_Return = 0xFF0D
XK_Escape = 0xFF1B
XK_Delete = 0xFFFF
XK_space = 0x20

RevertToParent = 2
CurrentTime = 0


class XColor(ctypes.Structure):
    _fields_ = [
        ("pixel", ctypes.c_ulong),
        ("red", ctypes.c_ushort),
        ("green", ctypes.c_ushort),
        ("blue", ctypes.c_ushort),
        ("flags", ctypes.c_char),
        ("pad", ctypes.c_char),
    ]


class XAnyEvent(ctypes.Structure):
    _fields_ = [
        ("type", ctypes.c_int),
        ("serial", ctypes.c_ulong),
        ("send_event", ctypes.c_int),
        ("display", ctypes.c_void_p),
        ("window", ctypes.c_ulong),
    ]


class XKeyEvent(ctypes.Structure):
    _fields_ = [
        ("type", ctypes.c_int),
        ("serial", ctypes.c_ulong),
        ("send_event", ctypes.c_int),
        ("display", ctypes.c_void_p),
        ("window", ctypes.c_ulong),
        ("root", ctypes.c_ulong),
        ("subwindow", ctypes.c_ulong),
        ("time", ctypes.c_ulong),
        ("x", ctypes.c_int),
        ("y", ctypes.c_int),
        ("x_root", ctypes.c_int),
        ("y_root", ctypes.c_int),
        ("state", ctypes.c_uint),
        ("keycode", ctypes.c_uint),
        ("same_screen", ctypes.c_int),
    ]


class XButtonEvent(ctypes.Structure):
    _fields_ = [
        ("type", ctypes.c_int),
        ("serial", ctypes.c_ulong),
        ("send_event", ctypes.c_int),
        ("display", ctypes.c_void_p),
        ("window", ctypes.c_ulong),
        ("root", ctypes.c_ulong),
        ("subwindow", ctypes.c_ulong),
        ("time", ctypes.c_ulong),
        ("x", ctypes.c_int),
        ("y", ctypes.c_int),
        ("x_root", ctypes.c_int),
        ("y_root", ctypes.c_int),
        ("state", ctypes.c_uint),
        ("button", ctypes.c_uint),
        ("same_screen", ctypes.c_int),
    ]


class XExposeEvent(ctypes.Structure):
    _fields_ = [
        ("type", ctypes.c_int),
        ("serial", ctypes.c_ulong),
        ("send_event", ctypes.c_int),
        ("display", ctypes.c_void_p),
        ("window", ctypes.c_ulong),
        ("x", ctypes.c_int),
        ("y", ctypes.c_int),
        ("width", ctypes.c_int),
        ("height", ctypes.c_int),
        ("count", ctypes.c_int),
    ]


class XClientMessageData(ctypes.Union):
    _fields_ = [
        ("b", ctypes.c_char * 20),
        ("s", ctypes.c_short * 10),
        ("l", ctypes.c_long * 5),
    ]


class XClientMessageEvent(ctypes.Structure):
    _fields_ = [
        ("type", ctypes.c_int),
        ("serial", ctypes.c_ulong),
        ("send_event", ctypes.c_int),
        ("display", ctypes.c_void_p),
        ("window", ctypes.c_ulong),
        ("message_type", ctypes.c_ulong),
        ("format", ctypes.c_int),
        ("data", XClientMessageData),
    ]


class XEvent(ctypes.Union):
    _fields_ = [
        ("type", ctypes.c_int),
        ("xany", XAnyEvent),
        ("xkey", XKeyEvent),
        ("xbutton", XButtonEvent),
        ("xexpose", XExposeEvent),
        ("xclient", XClientMessageEvent),
        ("pad", ctypes.c_long * 24),
    ]


class X11:
    def __init__(self):
        self.xlib = ctypes.CDLL("libX11.so.6")
        self.xtst = None
        try:
            self.xtst = ctypes.CDLL("libXtst.so.6")
        except OSError:
            self.xtst = None
        self._bind()

    def _bind(self):
        x = self.xlib
        x.XOpenDisplay.argtypes = [ctypes.c_char_p]
        x.XOpenDisplay.restype = ctypes.c_void_p
        x.XDefaultScreen.argtypes = [ctypes.c_void_p]
        x.XDefaultScreen.restype = ctypes.c_int
        x.XRootWindow.argtypes = [ctypes.c_void_p, ctypes.c_int]
        x.XRootWindow.restype = ctypes.c_ulong
        x.XBlackPixel.argtypes = [ctypes.c_void_p, ctypes.c_int]
        x.XBlackPixel.restype = ctypes.c_ulong
        x.XWhitePixel.argtypes = [ctypes.c_void_p, ctypes.c_int]
        x.XWhitePixel.restype = ctypes.c_ulong
        x.XDefaultColormap.argtypes = [ctypes.c_void_p, ctypes.c_int]
        x.XDefaultColormap.restype = ctypes.c_ulong
        x.XAllocNamedColor.argtypes = [
            ctypes.c_void_p,
            ctypes.c_ulong,
            ctypes.c_char_p,
            ctypes.POINTER(XColor),
            ctypes.POINTER(XColor),
        ]
        x.XAllocNamedColor.restype = ctypes.c_int
        x.XCreateSimpleWindow.argtypes = [
            ctypes.c_void_p,
            ctypes.c_ulong,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_uint,
            ctypes.c_uint,
            ctypes.c_uint,
            ctypes.c_ulong,
            ctypes.c_ulong,
        ]
        x.XCreateSimpleWindow.restype = ctypes.c_ulong
        x.XStoreName.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_char_p]
        x.XSelectInput.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_long]
        x.XMapWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        x.XCreateGC.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_void_p]
        x.XCreateGC.restype = ctypes.c_void_p
        x.XSetForeground.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_ulong]
        x.XDrawString.argtypes = [
            ctypes.c_void_p,
            ctypes.c_ulong,
            ctypes.c_void_p,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
        ]
        x.XDrawRectangle.argtypes = [
            ctypes.c_void_p,
            ctypes.c_ulong,
            ctypes.c_void_p,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_uint,
            ctypes.c_uint,
        ]
        x.XFillRectangle.argtypes = [
            ctypes.c_void_p,
            ctypes.c_ulong,
            ctypes.c_void_p,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_uint,
            ctypes.c_uint,
        ]
        x.XClearWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        x.XFlush.argtypes = [ctypes.c_void_p]
        x.XPending.argtypes = [ctypes.c_void_p]
        x.XPending.restype = ctypes.c_int
        x.XNextEvent.argtypes = [ctypes.c_void_p, ctypes.POINTER(XEvent)]
        x.XLookupString.argtypes = [
            ctypes.POINTER(XKeyEvent),
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.POINTER(ctypes.c_ulong),
            ctypes.c_void_p,
        ]
        x.XLookupString.restype = ctypes.c_int
        x.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
        x.XInternAtom.restype = ctypes.c_ulong
        x.XSetWMProtocols.argtypes = [
            ctypes.c_void_p,
            ctypes.c_ulong,
            ctypes.POINTER(ctypes.c_ulong),
            ctypes.c_int,
        ]
        x.XQueryTree.argtypes = [
            ctypes.c_void_p,
            ctypes.c_ulong,
            ctypes.POINTER(ctypes.c_ulong),
            ctypes.POINTER(ctypes.c_ulong),
            ctypes.POINTER(ctypes.POINTER(ctypes.c_ulong)),
            ctypes.POINTER(ctypes.c_uint),
        ]
        x.XQueryTree.restype = ctypes.c_int
        x.XFetchName.argtypes = [
            ctypes.c_void_p,
            ctypes.c_ulong,
            ctypes.POINTER(ctypes.c_char_p),
        ]
        x.XFetchName.restype = ctypes.c_int
        x.XFree.argtypes = [ctypes.c_void_p]
        x.XRaiseWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        x.XSetInputFocus.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_ulong]
        x.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        x.XKeysymToKeycode.restype = ctypes.c_uint

        if self.xtst is not None:
            self.xtst.XTestFakeKeyEvent.argtypes = [
                ctypes.c_void_p,
                ctypes.c_uint,
                ctypes.c_int,
                ctypes.c_ulong,
            ]
            self.xtst.XTestFakeKeyEvent.restype = ctypes.c_int


class ControlPanel:
    width = 780
    height = 640

    def __init__(self):
        self.x11 = X11()
        display_name = os.environ.get("DISPLAY", ":0").encode()
        self.display = self.x11.xlib.XOpenDisplay(display_name)
        if not self.display:
            raise RuntimeError("Cannot open X display. Set DISPLAY=:0 and start Matchbox/X first.")

        self.screen = self.x11.xlib.XDefaultScreen(self.display)
        self.root = self.x11.xlib.XRootWindow(self.display, self.screen)
        self.black = self.x11.xlib.XBlackPixel(self.display, self.screen)
        self.white = self.x11.xlib.XWhitePixel(self.display, self.screen)
        self.colormap = self.x11.xlib.XDefaultColormap(self.display, self.screen)
        self.colors = {
            "bg": self.color("#f3f4f6"),
            "panel": self.color("#ffffff"),
            "ink": self.color("#111827"),
            "muted": self.color("#4b5563"),
            "line": self.color("#9ca3af"),
            "button": self.color("#2563eb"),
            "button2": self.color("#0f766e"),
            "danger": self.color("#b91c1c"),
            "warn": self.color("#92400e"),
            "field": self.color("#ffffff"),
            "focus": self.color("#fef3c7"),
            "status": self.color("#111827"),
            "status_bg": self.color("#e5e7eb"),
        }
        self.window = self.x11.xlib.XCreateSimpleWindow(
            self.display,
            self.root,
            80,
            70,
            self.width,
            self.height,
            1,
            self.black,
            self.colors["bg"],
        )
        self.x11.xlib.XStoreName(self.display, self.window, b"KV260 Metavision Control Panel")
        masks = ExposureMask | ButtonPressMask | KeyPressMask | StructureNotifyMask
        self.x11.xlib.XSelectInput(self.display, self.window, masks)
        self.gc = self.x11.xlib.XCreateGC(self.display, self.window, 0, None)
        self.wm_delete = self.x11.xlib.XInternAtom(self.display, b"WM_DELETE_WINDOW", 0)
        protocols = (ctypes.c_ulong * 1)(self.wm_delete)
        self.x11.xlib.XSetWMProtocols(self.display, self.window, protocols, 1)

        self.fields = [
            {"id": "folder", "label": "Record folder", "value": DEFAULT_RECORD_DIR},
            {"id": "filename", "label": "File name", "value": self.default_filename()},
            {"id": "display", "label": "X display", "value": os.environ.get("DISPLAY", ":0")},
            {"id": "camera_config", "label": "Camera config JSON", "value": ""},
            {"id": "biases", "label": "Biases file", "value": ""},
            {"id": "output_config", "label": "Output config JSON", "value": os.path.join(DEFAULT_RECORD_DIR, "settings.json")},
            {"id": "roi", "label": "ROI x y w h", "value": ""},
            {"id": "subsampling", "label": "Subsampling r c", "value": ""},
        ]
        self.checks = {
            "restart_record": {"label": "Restart viewer when opening a recording file", "value": True},
            "rearm": {"label": "Rearm camera before next open", "value": False},
        }
        self.active_field = None
        self.field_rects = {}
        self.button_rects = {}
        self.check_rects = {}
        self.status_lines = [
            "Ready. Open Live for lowest latency, or Open Record to set a .raw output file.",
            "Native recording is toggled inside Metavision Viewer with SPACE; the panel can send SPACE too.",
        ]
        self.busy = False
        self.running = True
        self.dirty = True

    def color(self, spec):
        exact = XColor()
        screen = XColor()
        if self.x11.xlib.XAllocNamedColor(self.display, self.colormap, spec.encode(), ctypes.byref(screen), ctypes.byref(exact)):
            return screen.pixel
        return self.black

    @staticmethod
    def default_filename():
        return "event_%s.raw" % datetime.now().strftime("%Y%m%d_%H%M%S")

    def field(self, field_id):
        for item in self.fields:
            if item["id"] == field_id:
                return item
        raise KeyError(field_id)

    def field_value(self, field_id):
        return self.field(field_id)["value"].strip()

    def draw(self):
        x = self.x11.xlib
        x.XClearWindow(self.display, self.window)
        self.fill(0, 0, self.width, self.height, self.colors["bg"])
        self.text(22, 30, "KV260 Metavision Control Panel", self.colors["ink"])
        self.text(22, 52, "Live view, recording output, camera settings, and process control.", self.colors["muted"])

        y = 78
        self.field_rects = {}
        left_w = 155
        field_x = 180
        field_w = 570
        for item in self.fields:
            self.text(22, y + 20, item["label"], self.colors["muted"])
            fill = self.colors["focus"] if self.active_field == item["id"] else self.colors["field"]
            self.fill(field_x, y, field_w, 27, fill)
            self.rect(field_x, y, field_w, 27, self.colors["line"])
            value = self.elide(item["value"], 78)
            self.text(field_x + 7, y + 19, value, self.colors["ink"])
            self.field_rects[item["id"]] = (field_x, y, field_w, 27)
            y += 36

        self.check_rects = {}
        check_y = y + 2
        for check_id, check in self.checks.items():
            self.check_rects[check_id] = (22, check_y - 14, 17, 17)
            self.rect(22, check_y - 14, 17, 17, self.colors["line"])
            if check["value"]:
                self.fill(25, check_y - 11, 11, 11, self.colors["button2"])
            self.text(47, check_y, check["label"], self.colors["ink"])
            check_y += 26

        button_y = check_y + 8
        self.button_rects = {}
        self.button("new_name", "New Name", 22, button_y, 110, self.colors["button2"])
        self.button("make_folder", "Make Folder", 142, button_y, 120, self.colors["button2"])
        self.button("live", "Open Live", 272, button_y, 105, self.colors["button"])
        self.button("record", "Open Record", 387, button_y, 122, self.colors["button"])
        self.button("toggle_record", "Toggle Rec", 519, button_y, 110, self.colors["warn"])
        self.button("close_viewer", "Close Viewer", 639, button_y, 118, self.colors["danger"])

        button_y += 40
        self.button("recover", "Recover Camera", 22, button_y, 140, self.colors["warn"])
        self.button("status", "Status", 172, button_y, 90, self.colors["button2"])
        self.button("close_panel", "Close Panel", 272, button_y, 118, self.colors["danger"])

        status_y = button_y + 45
        self.fill(22, status_y, 735, 100, self.colors["status_bg"])
        self.rect(22, status_y, 735, 100, self.colors["line"])
        self.text(34, status_y + 20, "Status", self.colors["ink"])
        visible = self.status_lines[-4:]
        sy = status_y + 42
        for line in visible:
            self.text(34, sy, self.elide(line, 105), self.colors["status"])
            sy += 18

        if self.busy:
            self.text(660, 30, "Running...", self.colors["warn"])

        x.XFlush(self.display)
        self.dirty = False

    def button(self, name, label, x, y, w, color):
        self.fill(x, y, w, 28, color)
        self.rect(x, y, w, 28, self.black)
        self.text(x + 10, y + 19, label, self.white)
        self.button_rects[name] = (x, y, w, 28)

    def fill(self, x, y, w, h, color):
        self.x11.xlib.XSetForeground(self.display, self.gc, color)
        self.x11.xlib.XFillRectangle(self.display, self.window, self.gc, x, y, w, h)

    def rect(self, x, y, w, h, color):
        self.x11.xlib.XSetForeground(self.display, self.gc, color)
        self.x11.xlib.XDrawRectangle(self.display, self.window, self.gc, x, y, w, h)

    def text(self, x, y, text, color):
        data = str(text).encode("ascii", "replace")
        self.x11.xlib.XSetForeground(self.display, self.gc, color)
        self.x11.xlib.XDrawString(self.display, self.window, self.gc, x, y, data, len(data))

    @staticmethod
    def elide(text, max_len):
        text = str(text)
        if len(text) <= max_len:
            return text
        return text[: max_len - 3] + "..."

    @staticmethod
    def inside(rect, x, y):
        rx, ry, rw, rh = rect
        return rx <= x <= rx + rw and ry <= y <= ry + rh

    def set_status(self, text):
        lines = []
        for raw in str(text).splitlines():
            raw = raw.strip()
            if raw:
                lines.append(raw)
        if not lines:
            lines = ["Done."]
        self.status_lines = lines[-6:]
        self.dirty = True

    def expand_path(self, value):
        return os.path.abspath(os.path.expandvars(os.path.expanduser(value)))

    def record_path(self):
        folder = self.expand_path(self.field_value("folder") or DEFAULT_RECORD_DIR)
        filename = self.field_value("filename") or self.default_filename()
        if not filename.lower().endswith(".raw"):
            filename += ".raw"
        return os.path.join(folder, filename)

    def common_viewer_args(self):
        args = []
        pairs = [
            ("camera_config", "--input-camera-config"),
            ("biases", "--biases"),
            ("output_config", "--output-camera-config"),
            ("roi", "--roi"),
            ("subsampling", "--subsampling"),
        ]
        for field_id, flag in pairs:
            value = self.field_value(field_id)
            if value:
                if field_id in ("camera_config", "biases", "output_config"):
                    value = self.expand_path(value)
                args.extend([flag, value])
        return args

    def run_command_async(self, label, args, timeout=70):
        if self.busy:
            self.set_status("Busy: wait for the current command to finish.")
            return
        self.busy = True
        self.set_status("%s: %s" % (label, " ".join(shlex.quote(a) for a in args)))

        def worker():
            env = os.environ.copy()
            env["DISPLAY"] = self.field_value("display") or env.get("DISPLAY", ":0")
            env.setdefault("HOME", os.path.expanduser("~"))
            env["LC_ALL"] = "C"
            try:
                result = subprocess.run(
                    args,
                    cwd=PROJECT_DIR,
                    env=env,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    timeout=timeout,
                )
                output = result.stdout.strip()
                if output:
                    message = output
                else:
                    message = "%s completed with exit code %s." % (label, result.returncode)
                if result.returncode != 0:
                    message = "%s failed with exit code %s.\n%s" % (label, result.returncode, output)
                self.set_status(message)
            except subprocess.TimeoutExpired:
                self.set_status("%s timed out after %ss." % (label, timeout))
            except Exception as exc:
                self.set_status("%s failed: %s" % (label, exc))
            finally:
                self.busy = False
                self.dirty = True

        threading.Thread(target=worker, daemon=True).start()

    def open_live(self):
        args = [
            VIEWER_HELPER,
            "--start",
            "--display",
            self.field_value("display") or ":0",
            "--no-force",
            "--no-rearm",
            "--no-record",
            "--low-latency",
        ]
        if self.checks["rearm"]["value"]:
            args[5] = "--rearm"
        args.extend(self.common_viewer_args())
        self.run_command_async("Open live viewer", args)

    def open_record(self):
        output = self.record_path()
        try:
            os.makedirs(os.path.dirname(output), exist_ok=True)
        except Exception as exc:
            self.set_status("Could not create record folder: %s" % exc)
            return
        force = "--force" if self.checks["restart_record"]["value"] else "--no-force"
        rearm = "--rearm" if self.checks["rearm"]["value"] else "--no-rearm"
        args = [
            VIEWER_HELPER,
            "--start",
            "--display",
            self.field_value("display") or ":0",
            force,
            rearm,
            "--record",
            "--output-file",
            output,
        ]
        args.extend(self.common_viewer_args())
        self.run_command_async("Open recording viewer", args)

    def close_viewer(self):
        args = [VIEWER_HELPER, "--stop", "--force"]
        self.run_command_async("Close viewer", args, timeout=30)

    def recover_camera(self):
        args = [DESKTOP_HELPER, "--recover"]
        self.run_command_async("Recover camera", args, timeout=90)

    def refresh_status(self):
        args = [VIEWER_HELPER, "--status", "--display", self.field_value("display") or ":0"]
        self.run_command_async("Status", args, timeout=30)

    def new_name(self):
        self.field("filename")["value"] = self.default_filename()
        self.set_status("New recording filename: %s" % self.field_value("filename"))

    def make_folder(self):
        folder = self.expand_path(self.field_value("folder") or DEFAULT_RECORD_DIR)
        try:
            os.makedirs(folder, exist_ok=True)
            self.set_status("Folder ready: %s" % folder)
        except Exception as exc:
            self.set_status("Could not create folder: %s" % exc)

    def fetch_window_name(self, win):
        name = ctypes.c_char_p()
        if self.x11.xlib.XFetchName(self.display, win, ctypes.byref(name)) and name.value:
            try:
                text = name.value.decode("utf-8", "replace")
            finally:
                self.x11.xlib.XFree(name)
            return text
        return ""

    def find_metavision_window(self, start=None, depth=0):
        if start is None:
            start = self.root
        if depth > 8:
            return None
        name = self.fetch_window_name(start).lower()
        if start != self.window and ("metavision" in name or "event viewer" in name):
            return start

        root = ctypes.c_ulong()
        parent = ctypes.c_ulong()
        children = ctypes.POINTER(ctypes.c_ulong)()
        nchildren = ctypes.c_uint()
        ok = self.x11.xlib.XQueryTree(
            self.display,
            start,
            ctypes.byref(root),
            ctypes.byref(parent),
            ctypes.byref(children),
            ctypes.byref(nchildren),
        )
        if not ok or not children:
            return None
        try:
            for idx in range(nchildren.value):
                found = self.find_metavision_window(children[idx], depth + 1)
                if found:
                    return found
        finally:
            self.x11.xlib.XFree(children)
        return None

    def toggle_record(self):
        if self.x11.xtst is None:
            self.set_status("libXtst is not available; use SPACE in the Metavision Viewer window.")
            return
        win = self.find_metavision_window()
        if not win:
            self.set_status("No Metavision Viewer window found. Open Record first.")
            return
        keycode = self.x11.xlib.XKeysymToKeycode(self.display, XK_space)
        if not keycode:
            self.set_status("Could not map SPACE key.")
            return
        self.x11.xlib.XRaiseWindow(self.display, win)
        self.x11.xlib.XSetInputFocus(self.display, win, RevertToParent, CurrentTime)
        self.x11.xtst.XTestFakeKeyEvent(self.display, keycode, 1, CurrentTime)
        self.x11.xtst.XTestFakeKeyEvent(self.display, keycode, 0, CurrentTime)
        self.x11.xlib.XFlush(self.display)
        self.set_status("Sent SPACE to Metavision Viewer. Recording toggles if the viewer was opened with an output file.")

    def handle_button(self, name):
        actions = {
            "new_name": self.new_name,
            "make_folder": self.make_folder,
            "live": self.open_live,
            "record": self.open_record,
            "toggle_record": self.toggle_record,
            "close_viewer": self.close_viewer,
            "recover": self.recover_camera,
            "status": self.refresh_status,
            "close_panel": self.stop,
        }
        action = actions.get(name)
        if action:
            action()

    def handle_click(self, x, y):
        for field_id, rect in self.field_rects.items():
            if self.inside(rect, x, y):
                self.active_field = field_id
                self.dirty = True
                return
        for check_id, rect in self.check_rects.items():
            if self.inside(rect, x, y):
                self.checks[check_id]["value"] = not self.checks[check_id]["value"]
                self.dirty = True
                return
        for name, rect in self.button_rects.items():
            if self.inside(rect, x, y):
                self.handle_button(name)
                return
        self.active_field = None
        self.dirty = True

    def next_field(self):
        ids = [item["id"] for item in self.fields]
        if self.active_field not in ids:
            self.active_field = ids[0]
        else:
            self.active_field = ids[(ids.index(self.active_field) + 1) % len(ids)]
        self.dirty = True

    def handle_key(self, xkey):
        keysym = ctypes.c_ulong()
        buf = ctypes.create_string_buffer(16)
        n = self.x11.xlib.XLookupString(ctypes.byref(xkey), buf, 15, ctypes.byref(keysym), None)

        if keysym.value == XK_Escape:
            self.active_field = None
            self.dirty = True
            return
        if keysym.value == XK_Tab:
            self.next_field()
            return
        if keysym.value == XK_Return:
            self.refresh_status()
            return
        if not self.active_field:
            return

        field = self.field(self.active_field)
        if keysym.value in (XK_BackSpace, XK_Delete):
            field["value"] = field["value"][:-1]
        elif n > 0:
            text = buf.raw[:n].decode("ascii", "ignore")
            text = "".join(ch for ch in text if 32 <= ord(ch) < 127)
            if text:
                field["value"] += text
        self.dirty = True

    def stop(self):
        self.running = False

    def run(self):
        self.x11.xlib.XMapWindow(self.display, self.window)
        self.x11.xlib.XFlush(self.display)
        self.refresh_status()
        event = XEvent()
        while self.running:
            while self.x11.xlib.XPending(self.display):
                self.x11.xlib.XNextEvent(self.display, ctypes.byref(event))
                if event.type == Expose:
                    self.dirty = True
                elif event.type == ButtonPress:
                    self.handle_click(event.xbutton.x, event.xbutton.y)
                elif event.type == KeyPress:
                    self.handle_key(event.xkey)
                elif event.type == ClientMessage and event.xclient.data.l[0] == self.wm_delete:
                    self.stop()
            if self.dirty:
                self.draw()
            time.sleep(0.05)


def main():
    try:
        panel = ControlPanel()
        panel.run()
    except Exception as exc:
        sys.stderr.write("KV260 Metavision control panel failed: %s\n" % exc)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
