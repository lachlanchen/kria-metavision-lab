#!/usr/bin/env python3
"""Two-pane SSH/SCP file transfer GUI for the KV260 lab.

The app is intentionally dependency-light: GTK/PyGObject on the board and the
system ssh/scp tools for transfers. It can run on the KV260 HDMI desktop or over
SSH X forwarding from Windows, macOS, or Linux.
"""

import json
import os
import base64
import shlex
import shutil
import subprocess
import threading
import time
from dataclasses import dataclass
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk


PROJECT_DIR = Path(__file__).resolve().parents[1]
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
CONFIG_PATH = CONFIG_DIR / "kv260-file-transfer.json"
DEFAULT_LOCAL_PATH = str(Path.home())
DEFAULT_RECORDINGS_PATH = os.path.expanduser(os.environ.get("KV260_EVENT_RECORD_DIR", "~/event_recordings"))
DEFAULT_REMOTE_PATH = os.environ.get("KV260_REMOTE_FILE_ROOT", "C:/Users/Administrator/Projects/petalinux")


def human_size(value):
    if value is None:
        return ""
    try:
        size = float(value)
    except Exception:
        return ""
    units = ["B", "KB", "MB", "GB", "TB"]
    unit = 0
    while size >= 1024 and unit < len(units) - 1:
        size /= 1024.0
        unit += 1
    if unit == 0:
        return f"{int(size)} B"
    return f"{size:.1f} {units[unit]}"


def format_mtime(epoch):
    try:
        return time.strftime("%Y-%m-%d %H:%M", time.localtime(float(epoch)))
    except Exception:
        return ""


def load_config():
    defaults = {
        "remote_user_host": "Administrator@192.168.1.166",
        "remote_key": str(Path.home() / ".ssh" / "id_dropbear_rsa"),
        "remote_root": DEFAULT_REMOTE_PATH,
        "remote_os": "windows",
        "local_root": DEFAULT_LOCAL_PATH,
    }
    try:
        if CONFIG_PATH.exists():
            saved = json.loads(CONFIG_PATH.read_text())
            defaults.update({k: v for k, v in saved.items() if v is not None})
    except Exception:
        pass
    return defaults


def save_config(config):
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(config, indent=2, sort_keys=True))


def shell_literal(value):
    return shlex.quote(str(value))


def powershell_literal(value):
    return "'" + str(value).replace("'", "''") + "'"


def powershell_encoded(script):
    return base64.b64encode(script.encode("utf-16le")).decode("ascii")


def run_command(args, env=None, timeout=None):
    proc = subprocess.run(
        args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
        timeout=timeout,
    )
    if proc.returncode != 0:
        detail = proc.stderr.strip() or proc.stdout.strip() or f"exit {proc.returncode}"
        raise RuntimeError(detail)
    return proc.stdout


@dataclass
class RemoteConfig:
    user_host: str
    key: str
    password: str
    remote_os: str

    @property
    def target(self):
        return self.user_host.strip()

    def auth_prefix(self):
        if self.password and shutil.which("sshpass"):
            return ["sshpass", "-e"], {"SSHPASS": self.password}
        return [], {}

    def is_dropbear_ssh(self):
        try:
            proc = subprocess.run(
                ["ssh", "-V"],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=2,
            )
            return "Dropbear" in proc.stdout
        except Exception:
            return False

    def ssh_args(self):
        prefix, env = self.auth_prefix()
        args = prefix + ["ssh"]
        if self.is_dropbear_ssh():
            args += ["-y"]
        else:
            args += ["-o", "ConnectTimeout=8"]
            if not self.password:
                args += ["-o", "BatchMode=yes"]
        if self.key.strip():
            args += ["-i", self.key.strip()]
        args.append(self.target)
        return args, env

    def scp_args(self):
        prefix, env = self.auth_prefix()
        args = prefix + ["scp", "-r"]
        if self.key.strip():
            args += ["-i", self.key.strip()]
        return args, env

    def remote_spec(self, path):
        clean = str(path).replace("\\", "/")
        if self.remote_os == "posix":
            return f"{self.target}:{shell_literal(clean)}"
        return f"{self.target}:{clean}"


class FilePane(Gtk.Box):
    def __init__(self, title, is_remote=False):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.is_remote = is_remote
        self.path = DEFAULT_REMOTE_PATH if is_remote else DEFAULT_LOCAL_PATH
        self.on_open = None
        self.on_refresh = None
        self.on_up = None

        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        label = Gtk.Label(label=title)
        label.get_style_context().add_class("pane-title")
        label.set_xalign(0)
        header.pack_start(label, False, False, 0)
        self.path_entry = Gtk.Entry()
        self.path_entry.set_hexpand(True)
        self.path_entry.connect("activate", lambda _entry: self._emit_refresh())
        header.pack_start(self.path_entry, True, True, 0)
        up_button = Gtk.Button(label="Up")
        up_button.connect("clicked", lambda _button: self.on_up and self.on_up())
        header.pack_start(up_button, False, False, 0)
        refresh_button = Gtk.Button(label="Refresh")
        refresh_button.connect("clicked", lambda _button: self._emit_refresh())
        header.pack_start(refresh_button, False, False, 0)
        self.pack_start(header, False, False, 0)

        self.store = Gtk.ListStore(str, str, str, str, str, bool)
        self.tree = Gtk.TreeView(model=self.store)
        self.tree.set_headers_visible(True)
        self.tree.get_selection().set_mode(Gtk.SelectionMode.MULTIPLE)
        self.tree.connect("row-activated", self._row_activated)

        columns = [
            ("Name", 0, 280),
            ("Type", 1, 72),
            ("Size", 2, 86),
            ("Modified", 3, 130),
        ]
        for title_text, index, width in columns:
            renderer = Gtk.CellRendererText()
            column = Gtk.TreeViewColumn(title_text, renderer, text=index)
            column.set_resizable(True)
            column.set_min_width(50)
            column.set_fixed_width(width)
            self.tree.append_column(column)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scroller.add(self.tree)
        self.pack_start(scroller, True, True, 0)

    def _emit_refresh(self):
        self.path = self.path_entry.get_text().strip() or self.path
        if self.on_refresh:
            self.on_refresh()

    def _row_activated(self, _tree, path, _column):
        item = self.store[path]
        if bool(item[5]) and self.on_open:
            self.on_open(item[4])

    def set_path(self, path):
        self.path = str(path)
        self.path_entry.set_text(self.path)

    def set_entries(self, entries):
        self.store.clear()
        for entry in entries:
            self.store.append(
                [
                    entry["name"],
                    "Folder" if entry["is_dir"] else "File",
                    "" if entry["is_dir"] else human_size(entry.get("size")),
                    format_mtime(entry.get("mtime")),
                    entry["path"],
                    bool(entry["is_dir"]),
                ]
            )

    def selected_paths(self):
        model, rows = self.tree.get_selection().get_selected_rows()
        paths = []
        for row in rows:
            paths.append(model[row][4])
        return paths


class TransferApp(Gtk.Window):
    def __init__(self):
        super().__init__(title="KV260 File Transfer")
        self.set_default_size(1180, 720)
        self.set_border_width(14)
        self.config = load_config()
        self.remote_current = self.config["remote_root"]

        self._build_css()
        self._build_ui()
        self._load_initial_state()

    def _build_css(self):
        css = b"""
        window { background: #f6f8fb; }
        .title { font-size: 24px; font-weight: 700; color: #0f172a; }
        .subtitle { color: #475569; }
        .pane-title { font-weight: 700; color: #0f172a; }
        button.suggested { background: #2563eb; color: white; }
        button.success { background: #059669; color: white; }
        button.warning { background: #d97706; color: white; }
        textview logview { background: #0f172a; color: #e2e8f0; }
        """
        provider = Gtk.CssProvider()
        provider.load_from_data(css)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    def _build_ui(self):
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.add(outer)

        title = Gtk.Label(label="KV260 File Transfer")
        title.set_xalign(0)
        title.get_style_context().add_class("title")
        outer.pack_start(title, False, False, 0)

        subtitle = Gtk.Label(
            label="Two-pane SSH/SCP copy between this KV260 and a Windows, macOS, or Linux host."
        )
        subtitle.set_xalign(0)
        subtitle.get_style_context().add_class("subtitle")
        outer.pack_start(subtitle, False, False, 0)

        settings = Gtk.Grid(column_spacing=8, row_spacing=8)
        outer.pack_start(settings, False, False, 0)

        self.remote_entry = Gtk.Entry(text=self.config["remote_user_host"])
        self.key_entry = Gtk.Entry(text=self.config["remote_key"])
        self.password_entry = Gtk.Entry()
        self.password_entry.set_visibility(False)
        self.remote_root_entry = Gtk.Entry(text=self.config["remote_root"])
        self.os_combo = Gtk.ComboBoxText()
        for value, label in [("windows", "Windows"), ("posix", "Linux/macOS")]:
            self.os_combo.append(value, label)
        self.os_combo.set_active_id(self.config.get("remote_os", "windows"))

        fields = [
            ("Remote", self.remote_entry),
            ("Key", self.key_entry),
            ("Password", self.password_entry),
            ("Remote OS", self.os_combo),
            ("Remote Root", self.remote_root_entry),
        ]
        for index, (label_text, widget) in enumerate(fields):
            label = Gtk.Label(label=label_text)
            label.set_xalign(0)
            settings.attach(label, index * 2, 0, 1, 1)
            widget.set_hexpand(index in (0, 1, 4))
            settings.attach(widget, index * 2 + 1, 0, 1, 1)

        save_button = Gtk.Button(label="Save")
        save_button.connect("clicked", lambda _button: self.save_settings())
        settings.attach(save_button, 10, 0, 1, 1)

        paned = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)
        paned.set_wide_handle(True)
        outer.pack_start(paned, True, True, 0)

        self.local_pane = FilePane("KV260 Local")
        self.remote_pane = FilePane("Remote Host", is_remote=True)
        self.local_pane.on_refresh = self.refresh_local
        self.remote_pane.on_refresh = self.refresh_remote
        self.local_pane.on_open = lambda path: (self.local_pane.set_path(path), self.refresh_local())
        self.remote_pane.on_open = lambda path: (self.remote_pane.set_path(path), self.refresh_remote())
        self.local_pane.on_up = self.local_up
        self.remote_pane.on_up = self.remote_up
        paned.pack1(self.local_pane, True, False)
        paned.pack2(self.remote_pane, True, False)

        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        outer.pack_start(actions, False, False, 0)
        upload = Gtk.Button(label="Upload Selected ->")
        upload.get_style_context().add_class("success")
        upload.connect("clicked", lambda _button: self.upload_selected())
        actions.pack_start(upload, False, False, 0)
        download = Gtk.Button(label="<- Download Selected")
        download.get_style_context().add_class("suggested")
        download.connect("clicked", lambda _button: self.download_selected())
        actions.pack_start(download, False, False, 0)
        new_local = Gtk.Button(label="New Local Folder")
        new_local.connect("clicked", lambda _button: self.new_folder(False))
        actions.pack_start(new_local, False, False, 0)
        new_remote = Gtk.Button(label="New Remote Folder")
        new_remote.connect("clicked", lambda _button: self.new_folder(True))
        actions.pack_start(new_remote, False, False, 0)
        open_recordings = Gtk.Button(label="Recordings")
        open_recordings.connect("clicked", lambda _button: (self.local_pane.set_path(DEFAULT_RECORDINGS_PATH), self.refresh_local()))
        actions.pack_start(open_recordings, False, False, 0)

        self.progress = Gtk.ProgressBar()
        self.progress.set_show_text(True)
        self.progress.set_text("Idle")
        self.progress.set_hexpand(True)
        actions.pack_start(self.progress, True, True, 0)

        self.log_buffer = Gtk.TextBuffer()
        log_view = Gtk.TextView(buffer=self.log_buffer)
        log_view.set_editable(False)
        log_view.set_monospace(True)
        log_view.set_size_request(-1, 96)
        log_scroll = Gtk.ScrolledWindow()
        log_scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        log_scroll.add(log_view)
        outer.pack_start(log_scroll, False, False, 0)

    def _load_initial_state(self):
        self.local_pane.set_path(self.config.get("local_root", DEFAULT_LOCAL_PATH))
        self.remote_pane.set_path(self.config.get("remote_root", DEFAULT_REMOTE_PATH))
        self.refresh_local()
        self.refresh_remote()

    def save_settings(self):
        config = {
            "remote_user_host": self.remote_entry.get_text().strip(),
            "remote_key": self.key_entry.get_text().strip(),
            "remote_root": self.remote_pane.path_entry.get_text().strip() or self.remote_root_entry.get_text().strip(),
            "remote_os": self.os_combo.get_active_id() or "windows",
            "local_root": self.local_pane.path_entry.get_text().strip(),
        }
        save_config(config)
        self.log(f"Saved config: {CONFIG_PATH}")

    def remote_config(self):
        return RemoteConfig(
            user_host=self.remote_entry.get_text().strip(),
            key=self.key_entry.get_text().strip(),
            password=self.password_entry.get_text(),
            remote_os=self.os_combo.get_active_id() or "windows",
        )

    def set_busy(self, text):
        self.progress.pulse()
        self.progress.set_text(text)

    def set_idle(self, text="Idle"):
        self.progress.set_fraction(0)
        self.progress.set_text(text)

    def log(self, text):
        stamp = time.strftime("%H:%M:%S")
        self.log_buffer.insert(self.log_buffer.get_end_iter(), f"[{stamp}] {text}\n")

    def run_background(self, label, worker, done=None):
        self.set_busy(label)

        def thread_main():
            try:
                result = worker()
                GLib.idle_add(lambda: self._finish_background(label, None, result, done))
            except Exception as exc:
                GLib.idle_add(lambda: self._finish_background(label, exc, None, done))

        threading.Thread(target=thread_main, daemon=True).start()

    def _finish_background(self, label, error, result, done):
        if error:
            self.set_idle("Failed")
            self.log(f"{label} failed: {error}")
        else:
            self.set_idle("Done")
            if done:
                done(result)
        return False

    def refresh_local(self):
        path = Path(self.local_pane.path_entry.get_text().strip() or self.local_pane.path)
        if not path.exists():
            self.log(f"Local path does not exist: {path}")
            return
        entries = []
        for item in sorted(path.iterdir(), key=lambda p: (not p.is_dir(), p.name.lower())):
            try:
                stat = item.stat()
            except OSError:
                continue
            entries.append(
                {
                    "name": item.name,
                    "path": str(item),
                    "is_dir": item.is_dir(),
                    "size": stat.st_size,
                    "mtime": stat.st_mtime,
                }
            )
        self.local_pane.set_path(str(path))
        self.local_pane.set_entries(entries)

    def refresh_remote(self):
        path = self.remote_pane.path_entry.get_text().strip() or self.remote_pane.path
        cfg = self.remote_config()
        if not cfg.target:
            self.log("Remote host is empty.")
            return

        def worker():
            if cfg.remote_os == "windows":
                return self._list_remote_windows(cfg, path)
            return self._list_remote_posix(cfg, path)

        def done(result):
            self.remote_pane.set_path(result["path"])
            self.remote_root_entry.set_text(result["path"])
            self.remote_pane.set_entries(result["items"])
            self.log(f"Remote refreshed: {result['path']}")

        self.run_background("Refreshing remote", worker, done)

    def _list_remote_posix(self, cfg, path):
        code = (
            "import json, os, sys;"
            "p=os.path.abspath(sys.argv[1]);"
            "items=[];"
            "names=sorted(os.listdir(p), key=lambda n:(not os.path.isdir(os.path.join(p,n)), n.lower()));"
            "\nfor n in names:\n"
            " q=os.path.join(p,n); s=os.lstat(q);"
            " items.append({'name':n,'path':q,'is_dir':os.path.isdir(q),'size':s.st_size,'mtime':s.st_mtime})\n"
            "print(json.dumps({'path':p,'parent':os.path.dirname(p),'items':items}))"
        )
        args, env_add = cfg.ssh_args()
        env = os.environ.copy()
        env.update(env_add)
        out = run_command(args + [f"python3 -c {shell_literal(code)} {shell_literal(path)}"], env=env)
        return json.loads(out)

    def _list_remote_windows(self, cfg, path):
        ps_path = powershell_literal(path)
        ps = (
            "$ErrorActionPreference='Stop';"
            f"$p={ps_path};"
            "$resolved=(Resolve-Path -LiteralPath $p).Path;"
            "$items=Get-ChildItem -Force -LiteralPath $resolved | "
            "Sort-Object -Property @{Expression={$_.PSIsContainer};Descending=$true},Name | "
            "ForEach-Object {[PSCustomObject]@{name=$_.Name;path=($_.FullName -replace '\\\\','/');"
            "is_dir=$_.PSIsContainer;size=$(if ($_.PSIsContainer) {0} else {$_.Length});"
            "mtime=[int][DateTimeOffset]::new($_.LastWriteTime).ToUnixTimeSeconds()}};"
            "[PSCustomObject]@{path=($resolved -replace '\\\\','/');"
            "parent=((Split-Path -Parent $resolved) -replace '\\\\','/');items=$items} | "
            "ConvertTo-Json -Depth 5 -Compress"
        )
        args, env_add = cfg.ssh_args()
        env = os.environ.copy()
        env.update(env_add)
        out = run_command(
            args + [f"powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand {powershell_encoded(ps)}"],
            env=env,
        )
        return json.loads(out)

    def local_up(self):
        current = Path(self.local_pane.path_entry.get_text().strip() or self.local_pane.path)
        parent = current.parent if current.parent != current else current
        self.local_pane.set_path(str(parent))
        self.refresh_local()

    def remote_up(self):
        current = self.remote_pane.path_entry.get_text().strip() or self.remote_pane.path
        if self.os_combo.get_active_id() == "windows":
            normalized = current.rstrip("/\\")
            parent = normalized.rsplit("/", 1)[0] if "/" in normalized else normalized
        else:
            parent = str(Path(current).parent)
        self.remote_pane.set_path(parent or current)
        self.refresh_remote()

    def upload_selected(self):
        paths = self.local_pane.selected_paths()
        if not paths:
            self.log("No local files selected.")
            return
        remote_dir = self.remote_pane.path_entry.get_text().strip() or self.remote_pane.path
        cfg = self.remote_config()

        def worker():
            args, env_add = cfg.scp_args()
            env = os.environ.copy()
            env.update(env_add)
            for path in paths:
                run_command(args + [path, cfg.remote_spec(remote_dir) + "/"], env=env)
            return len(paths)

        self.run_background(f"Uploading {len(paths)} item(s)", worker, lambda count: (self.log(f"Uploaded {count} item(s)."), self.refresh_remote()))

    def download_selected(self):
        paths = self.remote_pane.selected_paths()
        if not paths:
            self.log("No remote files selected.")
            return
        local_dir = self.local_pane.path_entry.get_text().strip() or self.local_pane.path
        cfg = self.remote_config()

        def worker():
            args, env_add = cfg.scp_args()
            env = os.environ.copy()
            env.update(env_add)
            for path in paths:
                run_command(args + [cfg.remote_spec(path), local_dir], env=env)
            return len(paths)

        self.run_background(f"Downloading {len(paths)} item(s)", worker, lambda count: (self.log(f"Downloaded {count} item(s)."), self.refresh_local()))

    def new_folder(self, remote):
        dialog = Gtk.Dialog(title="New Folder", transient_for=self, flags=0)
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, Gtk.STOCK_OK, Gtk.ResponseType.OK)
        box = dialog.get_content_area()
        entry = Gtk.Entry()
        entry.set_placeholder_text("folder-name")
        box.add(entry)
        dialog.show_all()
        response = dialog.run()
        name = entry.get_text().strip()
        dialog.destroy()
        if response != Gtk.ResponseType.OK or not name:
            return

        if remote:
            base = self.remote_pane.path_entry.get_text().strip() or self.remote_pane.path
            cfg = self.remote_config()

            def worker():
                target = (base.rstrip("/\\") + "/" + name).replace("\\", "/")
                args, env_add = cfg.ssh_args()
                env = os.environ.copy()
                env.update(env_add)
                if cfg.remote_os == "windows":
                    ps = f"New-Item -ItemType Directory -Force -Path {powershell_literal(target)} | Out-Null"
                    run_command(
                        args + [f"powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand {powershell_encoded(ps)}"],
                        env=env,
                    )
                else:
                    run_command(args + [f"mkdir -p {shell_literal(target)}"], env=env)
                return target

            self.run_background("Creating remote folder", worker, lambda _target: self.refresh_remote())
        else:
            base = Path(self.local_pane.path_entry.get_text().strip() or self.local_pane.path)
            try:
                (base / name).mkdir(parents=True, exist_ok=True)
                self.refresh_local()
            except Exception as exc:
                self.log(f"New local folder failed: {exc}")


def main():
    app = TransferApp()
    app.connect("destroy", Gtk.main_quit)
    app.show_all()
    Gtk.main()


if __name__ == "__main__":
    main()
