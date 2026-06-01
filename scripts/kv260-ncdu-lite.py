#!/usr/bin/env python3
"""Small ncdu-style disk usage browser for constrained PetaLinux images."""

from __future__ import annotations

import argparse
import curses
import os
import stat
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, Optional


SKIP_DIRS = {
    "/proc",
    "/sys",
    "/dev",
    "/run",
    "/tmp",
    "/var/volatile",
    "/configfs",
}


@dataclass
class Node:
    path: str
    name: str
    size: int = 0
    is_dir: bool = False
    error: str = ""
    children: list["Node"] = field(default_factory=list)


def human_size(size: int) -> str:
    units = ("B", "K", "M", "G", "T")
    value = float(size)
    for unit in units:
        if value < 1024.0 or unit == units[-1]:
            if unit == "B":
                return f"{int(value):>5}{unit}"
            return f"{value:>5.1f}{unit}"
        value /= 1024.0
    return f"{size}B"


def blocks_size(st: os.stat_result) -> int:
    blocks = getattr(st, "st_blocks", 0)
    if blocks:
        return int(blocks) * 512
    return int(st.st_size)


def same_or_child(path: str, roots: Iterable[str]) -> bool:
    real = os.path.realpath(path)
    for root in roots:
        if real == root or real.startswith(root + os.sep):
            return True
    return False


def scan(path: str, root_dev: Optional[int], skip_mounts: bool) -> Node:
    try:
        st = os.lstat(path)
    except OSError as exc:
        return Node(path=path, name=os.path.basename(path) or path, error=str(exc))

    is_dir = stat.S_ISDIR(st.st_mode)
    node = Node(path=path, name=os.path.basename(path) or path, size=blocks_size(st), is_dir=is_dir)
    if not is_dir:
        return node

    real_path = os.path.realpath(path)
    if same_or_child(real_path, SKIP_DIRS):
        node.error = "skipped pseudo filesystem"
        return node

    if skip_mounts and root_dev is not None and st.st_dev != root_dev:
        node.error = "skipped other filesystem"
        return node

    try:
        entries = list(os.scandir(path))
    except OSError as exc:
        node.error = str(exc)
        return node

    total = node.size
    children: list[Node] = []
    for entry in entries:
        child_path = entry.path
        try:
            if entry.is_symlink():
                child_st = os.lstat(child_path)
                child = Node(
                    path=child_path,
                    name=entry.name,
                    size=blocks_size(child_st),
                    is_dir=False,
                )
            else:
                child = scan(child_path, root_dev, skip_mounts)
        except OSError as exc:
            child = Node(path=child_path, name=entry.name, error=str(exc))
        total += child.size
        children.append(child)

    node.children = sorted(children, key=lambda item: item.size, reverse=True)
    node.size = total
    return node


def flatten_top(node: Node, limit: int) -> list[Node]:
    return sorted(node.children, key=lambda item: item.size, reverse=True)[:limit]


def print_summary(root: Node, limit: int) -> None:
    print(f"Scanned: {root.path}")
    print(f"Total:   {human_size(root.size).strip()}")
    if root.error:
        print(f"Note:    {root.error}")
    print()
    for child in flatten_top(root, limit):
        marker = "/" if child.is_dir else " "
        note = f"  [{child.error}]" if child.error else ""
        print(f"{human_size(child.size)}  {marker} {child.name}{note}")


def find_child_index(nodes: list[Node], selected: Node) -> int:
    for index, item in enumerate(nodes):
        if item.path == selected.path:
            return index
    return 0


def draw(stdscr: "curses._CursesWindow", stack: list[Node], selected: int, offset: int) -> None:
    stdscr.erase()
    height, width = stdscr.getmaxyx()
    node = stack[-1]
    title = f" ncdu-lite {node.path}  total {human_size(node.size).strip()} "
    stdscr.addnstr(0, 0, title, width - 1, curses.A_REVERSE)
    help_text = " q quit  enter open  left/backspace parent  r rescan  ? help "
    stdscr.addnstr(1, 0, help_text, width - 1)
    if node.error:
        stdscr.addnstr(2, 0, f"Note: {node.error}", width - 1, curses.A_BOLD)
    row_start = 3
    visible = max(1, height - row_start)
    rows = node.children[offset : offset + visible]
    for row, child in enumerate(rows, start=row_start):
        actual_index = offset + row - row_start
        prefix = ">" if actual_index == selected else " "
        suffix = "/" if child.is_dir else " "
        error = f" [{child.error}]" if child.error else ""
        line = f"{prefix} {human_size(child.size)} {suffix} {child.name}{error}"
        attr = curses.A_REVERSE if actual_index == selected else curses.A_NORMAL
        stdscr.addnstr(row, 0, line, width - 1, attr)
    stdscr.refresh()


def show_help(stdscr: "curses._CursesWindow") -> None:
    stdscr.erase()
    lines = [
        "ncdu-lite help",
        "",
        "This is a small local replacement installed because the PetaLinux feed",
        "does not provide the official ncdu package.",
        "",
        "Keys:",
        "  up/down, k/j       move",
        "  enter/right/l      open directory",
        "  left/backspace/h   parent directory",
        "  r                  rescan current directory",
        "  q                  quit",
        "",
        "Pseudo filesystems such as /proc, /sys, /dev, /run and /tmp are skipped.",
        "Press any key to return.",
    ]
    for y, line in enumerate(lines):
        stdscr.addnstr(y, 0, line, curses.COLS - 1)
    stdscr.refresh()
    stdscr.getch()


def browse(stdscr: "curses._CursesWindow", root_path: str, skip_mounts: bool) -> None:
    curses.curs_set(0)
    root_dev = os.lstat(root_path).st_dev if skip_mounts else None
    stack = [scan(root_path, root_dev, skip_mounts)]
    selected = 0
    offset = 0
    while True:
        node = stack[-1]
        max_index = max(0, len(node.children) - 1)
        selected = min(selected, max_index)
        height, _ = stdscr.getmaxyx()
        visible = max(1, height - 3)
        if selected < offset:
            offset = selected
        if selected >= offset + visible:
            offset = selected - visible + 1
        draw(stdscr, stack, selected, offset)
        key = stdscr.getch()
        if key in (ord("q"), 27):
            return
        if key in (curses.KEY_DOWN, ord("j")):
            selected = min(max_index, selected + 1)
        elif key in (curses.KEY_UP, ord("k")):
            selected = max(0, selected - 1)
        elif key in (curses.KEY_NPAGE,):
            selected = min(max_index, selected + visible)
        elif key in (curses.KEY_PPAGE,):
            selected = max(0, selected - visible)
        elif key in (curses.KEY_RIGHT, ord("\n"), ord("\r"), ord("l")):
            if node.children and node.children[selected].is_dir:
                stack.append(node.children[selected])
                selected = 0
                offset = 0
        elif key in (curses.KEY_LEFT, curses.KEY_BACKSPACE, 127, 8, ord("h")):
            if len(stack) > 1:
                child = stack.pop()
                selected = find_child_index(stack[-1].children, child)
                offset = max(0, selected - visible // 2)
        elif key == ord("r"):
            current = stack[-1].path
            stack[-1] = scan(current, root_dev, skip_mounts)
            selected = 0
            offset = 0
        elif key == ord("?"):
            show_help(stdscr)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Small ncdu-style disk usage browser for constrained PetaLinux images."
    )
    parser.add_argument("path", nargs="?", default=".", help="path to scan")
    parser.add_argument("-x", "--one-file-system", action="store_true", help="stay on the starting filesystem")
    parser.add_argument("--cross-file-system", action="store_true", help="scan mounted filesystems too")
    parser.add_argument("--summary", action="store_true", help="print a non-interactive top-level summary")
    parser.add_argument("--limit", type=int, default=30, help="summary row limit")
    parser.add_argument("--version", action="store_true", help="show version and exit")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.version:
        print("ncdu-lite 0.1 for KV260 PetaLinux")
        return 0

    path = os.path.abspath(os.path.expanduser(args.path))
    if not os.path.exists(path):
        print(f"ncdu: {path}: no such file or directory", file=sys.stderr)
        return 1

    skip_mounts = args.one_file_system or (path == "/" and not args.cross_file_system)
    root_dev = os.lstat(path).st_dev if skip_mounts else None

    if args.summary or not sys.stdout.isatty():
        print_summary(scan(path, root_dev, skip_mounts), args.limit)
        return 0

    curses.wrapper(browse, path, skip_mounts)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
