#!/usr/bin/env python3
"""Print a JSON directory listing for the KV260 Control Center."""

import json
import os
import sys


def main():
    if len(sys.argv) != 2:
        print("usage: kv260-list-files-json.py PATH", file=sys.stderr)
        return 2

    path = os.path.abspath(sys.argv[1])
    items = []
    for name in sorted(os.listdir(path), key=lambda n: (not os.path.isdir(os.path.join(path, n)), n.lower())):
        item_path = os.path.join(path, name)
        try:
            stat = os.lstat(item_path)
        except OSError:
            continue
        items.append(
            {
                "name": name,
                "path": item_path,
                "is_dir": os.path.isdir(item_path),
                "size": stat.st_size,
                "mtime": stat.st_mtime,
            }
        )

    print(json.dumps({"path": path, "parent": os.path.dirname(path), "items": items}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
