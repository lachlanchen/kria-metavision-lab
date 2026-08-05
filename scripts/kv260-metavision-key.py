#!/usr/bin/env python3
"""Send one key to the native Metavision viewer through XTEST."""

from __future__ import annotations

import argparse
import ctypes
import ctypes.util


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("key", nargs="?", default="space")
    parser.add_argument("--display", default=":0")
    parser.add_argument("--title", default="CD Events")
    args = parser.parse_args()

    x11 = ctypes.CDLL(ctypes.util.find_library("X11") or "libX11.so.6")
    xtst = ctypes.CDLL(ctypes.util.find_library("Xtst") or "libXtst.so.6")
    window = ctypes.c_ulong
    display = ctypes.c_void_p
    window_pointer = ctypes.POINTER(window)

    x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
    x11.XOpenDisplay.restype = display
    x11.XDefaultRootWindow.argtypes = [display]
    x11.XDefaultRootWindow.restype = window
    x11.XQueryTree.argtypes = [
        display,
        window,
        ctypes.POINTER(window),
        ctypes.POINTER(window),
        ctypes.POINTER(window_pointer),
        ctypes.POINTER(ctypes.c_uint),
    ]
    x11.XFetchName.argtypes = [display, window, ctypes.POINTER(ctypes.c_char_p)]
    x11.XFree.argtypes = [ctypes.c_void_p]
    x11.XStringToKeysym.argtypes = [ctypes.c_char_p]
    x11.XStringToKeysym.restype = ctypes.c_ulong
    x11.XKeysymToKeycode.argtypes = [display, ctypes.c_ulong]
    x11.XKeysymToKeycode.restype = ctypes.c_uint
    x11.XSetInputFocus.argtypes = [display, window, ctypes.c_int, ctypes.c_ulong]
    x11.XFlush.argtypes = [display]
    xtst.XTestFakeKeyEvent.argtypes = [display, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]

    connection = x11.XOpenDisplay(args.display.encode("ascii"))
    if not connection:
        raise SystemExit(f"cannot open X display {args.display}")
    root = x11.XDefaultRootWindow(connection)

    def children(parent: int) -> list[int]:
        returned_root = window()
        returned_parent = window()
        items = window_pointer()
        count = ctypes.c_uint()
        ok = x11.XQueryTree(
            connection,
            parent,
            ctypes.byref(returned_root),
            ctypes.byref(returned_parent),
            ctypes.byref(items),
            ctypes.byref(count),
        )
        result = [int(items[index]) for index in range(count.value)] if ok and items else []
        if items:
            x11.XFree(items)
        return result

    def title(item: int) -> str:
        value = ctypes.c_char_p()
        if not x11.XFetchName(connection, item, ctypes.byref(value)) or not value.value:
            return ""
        result = value.value.decode("utf-8", "replace")
        x11.XFree(value)
        return result

    target_title = args.title.casefold()
    stack = [(int(root), 0)]
    candidates: list[tuple[int, int]] = []
    while stack:
        item, depth = stack.pop()
        if target_title in title(item).casefold():
            candidates.append((depth, item))
        stack.extend((child, depth + 1) for child in children(item))
    if not candidates:
        raise SystemExit(f"viewer window containing {args.title!r} was not found")

    _, target = max(candidates)
    x11.XSetInputFocus(connection, target, 2, 0)
    keysym = x11.XStringToKeysym(args.key.encode("ascii"))
    keycode = x11.XKeysymToKeycode(connection, keysym)
    if not keycode:
        raise SystemExit(f"unknown X11 key {args.key!r}")
    xtst.XTestFakeKeyEvent(connection, keycode, 1, 0)
    xtst.XTestFakeKeyEvent(connection, keycode, 0, 0)
    x11.XFlush(connection)
    print(f"sent {args.key} to 0x{target:x}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
