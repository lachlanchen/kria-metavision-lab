#!/usr/bin/env python3
"""Simple frame camera viewer for KV260 (V4L2) using OpenCV."""

from __future__ import annotations

import argparse
import os
import signal
import sys

try:
    import cv2
except ModuleNotFoundError:
    print("ERROR: python3 cv2 (OpenCV) is not installed.", file=sys.stderr)
    raise SystemExit(1)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", required=True, help="V4L2 frame device, e.g. /dev/video0")
    parser.add_argument(
        "--fps",
        type=float,
        default=0,
        help="Target FPS. 0 uses native stream pacing.",
    )
    parser.add_argument("--title", default="KV260 Frame Camera", help="Window title")
    parser.add_argument("--width", type=int, default=0, help="Optional capture width")
    parser.add_argument("--height", type=int, default=0, help="Optional capture height")
    return parser.parse_args()


def format_wait_ms(fps: float) -> int:
    if fps <= 0:
        return 1
    wait = int(1000.0 / fps)
    return max(1, wait)


def main() -> None:
    args = parse_args()

    if not os.path.exists(args.device):
        print(f"ERROR: device does not exist: {args.device}", file=sys.stderr)
        raise SystemExit(2)

    cap = cv2.VideoCapture(args.device, cv2.CAP_V4L2)
    if not cap.isOpened():
        print(f"ERROR: cannot open frame camera {args.device}", file=sys.stderr)
        raise SystemExit(2)

    if args.width > 0:
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
    if args.height > 0:
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)

    running = True

    def stop(_signum, _frame):
        nonlocal running
        running = False

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    wait_ms = format_wait_ms(args.fps)
    try:
        while running:
            ret, frame = cap.read()
            if not ret:
                print("ERROR: frame camera returned no frame", file=sys.stderr)
                break
            cv2.imshow(args.title, frame)
            key = cv2.waitKey(wait_ms) & 0xFF
            if key in (ord("q"), 27):  # q or Esc
                break
    finally:
        cap.release()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
