#!/usr/bin/env python3
"""Reduce an official Metavision EVT2.1 RAW file to ON/OFF time bins."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import numpy as np


POPCOUNT8 = np.array([bin(value).count("1") for value in range(256)], dtype=np.uint8)
LEGAL_TYPES = np.array([0, 1, 8], dtype=np.uint64)


def raw_payload_offset(path: Path) -> tuple[int, dict[str, str]]:
    metadata: dict[str, str] = {}
    with path.open("rb") as handle:
        first = handle.read(1)
        handle.seek(0)
        if first != b"%":
            return 0, metadata
        while True:
            line = handle.readline()
            if not line:
                raise RuntimeError("Metavision RAW header has no '% end' marker")
            text = line.decode("ascii", "replace").strip()
            if text == "% end":
                return handle.tell(), metadata
            if text.startswith("% "):
                key, _, value = text[2:].partition(" ")
                metadata[key] = value


def grow(values: np.ndarray, size: int) -> np.ndarray:
    if size <= values.size:
        return values
    expanded = np.zeros(max(size, max(1024, values.size * 2)), dtype=np.uint64)
    expanded[: values.size] = values
    return expanded


def decode(
    path: Path, bin_us: int, chunk_words: int, *,
    roi: tuple[int, int, int, int] | None = None,
    spatial: bool = False,
) -> dict[str, object]:
    offset, header = raw_payload_offset(path)
    on = np.zeros(0, dtype=np.uint64)
    off = np.zeros(0, dtype=np.uint64)
    layout: str | None = None
    current_high = np.int64(0)
    previous_raw_high: int | None = None
    high_wraps = 0
    base_time_set = False
    origin: int | None = None
    last_timestamp = 0
    words_total = 0
    cd_words = 0
    cd_events = 0
    remainder = b""
    high_modulus = 1 << 28
    high_wrap_guard = high_modulus // 2
    spatial_on = np.zeros((720, 1280), dtype=np.uint64) if spatial else None
    spatial_off = np.zeros((720, 1280), dtype=np.uint64) if spatial else None

    with path.open("rb") as handle:
        handle.seek(offset)
        while True:
            payload = remainder + handle.read(chunk_words * 8)
            usable = len(payload) - len(payload) % 8
            remainder = payload[usable:]
            if not usable:
                break
            words = np.frombuffer(payload[:usable], dtype="<u8")
            words_total += int(words.size)
            if layout is None:
                legacy_type = (words >> np.uint64(28)) & np.uint64(0xF)
                native_type = (words >> np.uint64(60)) & np.uint64(0xF)
                legacy_score = float(np.mean(np.isin(legacy_type, LEGAL_TYPES)))
                native_score = float(np.mean(np.isin(native_type, LEGAL_TYPES)))
                if max(legacy_score, native_score) < 0.90:
                    raise RuntimeError(
                        "EVT2.1 layout detection failed: "
                        f"legacy={legacy_score:.3f}, native={native_score:.3f}"
                    )
                layout = "legacy" if legacy_score > native_score else "native"

            event_type = (
                (words >> np.uint64(28)) & np.uint64(0xF)
                if layout == "legacy"
                else (words >> np.uint64(60)) & np.uint64(0xF)
            )
            high_mask = event_type == np.uint64(8)
            if np.any(high_mask):
                positions = np.flatnonzero(high_mask)
                raw_high = (
                    (words[high_mask] & np.uint64(0x0FFFFFFF)).astype(np.int64)
                    if layout == "legacy"
                    else (
                        (words[high_mask] >> np.uint64(32)) & np.uint64(0x0FFFFFFF)
                    ).astype(np.int64)
                )
                previous = np.empty(raw_high.size, dtype=np.int64)
                previous[0] = raw_high[0] if previous_raw_high is None else previous_raw_high
                previous[1:] = raw_high[:-1]
                wraps = (previous - raw_high) >= high_wrap_guard
                cumulative = high_wraps + np.cumsum(wraps, dtype=np.int64)
                extended = raw_high + cumulative * high_modulus
                high_wraps = int(cumulative[-1])
                previous_raw_high = int(raw_high[-1])
                values = np.zeros(words.size, dtype=np.int64)
                values[positions] = extended << 6
                high_at = np.where(high_mask, np.arange(words.size), -1)
                last_high = np.maximum.accumulate(high_at)
                base = np.full(words.size, current_high, dtype=np.int64)
                seen = last_high >= 0
                base[seen] = values[last_high[seen]]
                current_high = np.int64(values[positions[-1]])
                time_valid = seen | base_time_set
                base_time_set = True
            else:
                base = np.full(words.size, current_high, dtype=np.int64)
                time_valid = np.full(words.size, base_time_set, dtype=bool)

            cd = ((event_type == 0) | (event_type == 1)) & time_valid
            if not np.any(cd):
                continue
            selected = words[cd]
            selected_types = event_type[cd]
            if layout == "legacy":
                x = ((selected >> np.uint64(11)) & np.uint64(0x7FF)).astype(np.int32)
                y = (selected & np.uint64(0x7FF)).astype(np.int32)
                vectors = (selected >> np.uint64(32)).astype(np.uint32)
                low = (selected >> np.uint64(22)) & np.uint64(0x3F)
            else:
                x = ((selected >> np.uint64(43)) & np.uint64(0x7FF)).astype(np.int32)
                y = ((selected >> np.uint64(32)) & np.uint64(0x7FF)).astype(np.int32)
                vectors = (selected & np.uint64(0xFFFFFFFF)).astype(np.uint32)
                low = (selected >> np.uint64(54)) & np.uint64(0x3F)
            valid = (x < 1280) & (y < 720) & (vectors != 0)
            if not np.any(valid):
                continue
            vectors = vectors[valid]
            x = x[valid]
            y = y[valid]
            selected_types = selected_types[valid]
            word_counts = np.sum(
                POPCOUNT8[vectors.view(np.uint8).reshape(-1, 4)], axis=1
            ).astype(np.uint64)
            if roi is None:
                counts = word_counts
            else:
                x0, y0, x1, y1 = roi
                counts = np.zeros(vectors.size, dtype=np.uint64)
                row_ok = (y >= y0) & (y < y1)
                for bit in range(32):
                    pixel_x = x + bit
                    bit_set = ((vectors >> np.uint32(bit)) & np.uint32(1)) != 0
                    counts += (
                        bit_set & row_ok & (pixel_x >= x0) & (pixel_x < x1)
                    ).astype(np.uint64)
            if spatial:
                polarities_all = selected_types == 1
                assert spatial_on is not None and spatial_off is not None
                center_x = np.minimum(x + 15, 1279)
                flat = y.astype(np.int64) * 1280 + center_x.astype(np.int64)
                if np.any(polarities_all):
                    histogram = np.bincount(
                        flat[polarities_all], weights=word_counts[polarities_all],
                        minlength=720 * 1280,
                    ).reshape(720, 1280)
                    spatial_on += histogram.astype(np.uint64)
                if np.any(~polarities_all):
                    histogram = np.bincount(
                        flat[~polarities_all], weights=word_counts[~polarities_all],
                        minlength=720 * 1280,
                    ).reshape(720, 1280)
                    spatial_off += histogram.astype(np.uint64)
            timestamps = (base[cd][valid] + low[valid]).astype(np.int64)
            nonzero = counts > 0
            if not np.any(nonzero):
                continue
            counts = counts[nonzero]
            timestamps = timestamps[nonzero]
            selected_types = selected_types[nonzero]
            if origin is None:
                origin = int(np.min(timestamps))
            bins = ((timestamps - origin) // bin_us).astype(np.int64)
            keep = bins >= 0
            if not np.any(keep):
                continue
            bins = bins[keep]
            counts = counts[keep]
            polarities = (selected_types[keep] == 1)
            size = int(np.max(bins)) + 1
            on = grow(on, size)
            off = grow(off, size)
            if np.any(polarities):
                values = np.bincount(
                    bins[polarities], weights=counts[polarities], minlength=size
                ).astype(np.uint64)
                on[:size] += values
            if np.any(~polarities):
                values = np.bincount(
                    bins[~polarities], weights=counts[~polarities], minlength=size
                ).astype(np.uint64)
                off[:size] += values
            cd_words += int(len(selected))
            cd_events += int(np.sum(counts))
            last_timestamp = max(last_timestamp, int(np.max(timestamps)))

    if origin is None or layout is None:
        raise RuntimeError("RAW file contains no decodable CD events")
    used = max(1, int((last_timestamp - origin) // bin_us) + 1)
    return {
        "header": header,
        "layout": layout,
        "payload_offset": offset,
        "raw_bytes": path.stat().st_size,
        "words_total": words_total,
        "cd_words": cd_words,
        "cd_events": cd_events,
        "origin_us": origin,
        "span_us": last_timestamp - origin,
        "time_high_wraps": high_wraps,
        "bin_us": bin_us,
        "roi": list(roi) if roi is not None else None,
        "spatial_localization": (
            "vector-weighted x_base+15; horizontal uncertainty <=16 px"
            if spatial else None
        ),
        "on": on[:used],
        "off": off[:used],
        "spatial_on": spatial_on,
        "spatial_off": spatial_off,
    }


def parse_roi(value: str) -> tuple[int, int, int, int]:
    try:
        x0, y0, x1, y1 = (int(part) for part in value.split(","))
    except (TypeError, ValueError) as exc:
        raise argparse.ArgumentTypeError("ROI must be x0,y0,x1,y1") from exc
    if not (0 <= x0 < x1 <= 1280 and 0 <= y0 < y1 <= 720):
        raise argparse.ArgumentTypeError("ROI must fit 1280x720 and have positive area")
    return x0, y0, x1, y1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("raw", type=Path)
    parser.add_argument("--output-prefix", type=Path, required=True)
    parser.add_argument("--bin-us", type=int, default=1000)
    parser.add_argument("--chunk-words", type=int, default=1_000_000)
    parser.add_argument("--roi", type=parse_roi)
    parser.add_argument("--spatial", action="store_true")
    parser.add_argument("--delete-raw", action="store_true")
    args = parser.parse_args()
    if args.bin_us < 1:
        raise SystemExit("--bin-us must be positive")
    result = decode(
        args.raw, args.bin_us, args.chunk_words, roi=args.roi, spatial=args.spatial,
    )
    prefix = args.output_prefix
    prefix.parent.mkdir(parents=True, exist_ok=True)
    csv_path = prefix.with_suffix(".csv")
    json_path = prefix.with_suffix(".json")
    on = result.pop("on")
    off = result.pop("off")
    spatial_on = result.pop("spatial_on")
    spatial_off = result.pop("spatial_off")
    with csv_path.open("w", newline="", encoding="ascii") as handle:
        writer = csv.writer(handle)
        writer.writerow(["bin_start_us", "on_events", "off_events", "total_events"])
        for index, (on_count, off_count) in enumerate(zip(on, off)):
            writer.writerow([
                index * args.bin_us,
                int(on_count),
                int(off_count),
                int(on_count + off_count),
            ])
    result["bins"] = int(len(on))
    result["on_events"] = int(np.sum(on))
    result["off_events"] = int(np.sum(off))
    result["average_rate_eps"] = (
        (result["on_events"] + result["off_events"])
        / max(float(result["span_us"]) / 1e6, args.bin_us / 1e6)
    )
    result["raw"] = str(args.raw)
    result["csv"] = str(csv_path)
    if args.spatial:
        spatial_path = prefix.with_name(prefix.name + "_spatial.npz")
        np.savez_compressed(spatial_path, on=spatial_on, off=spatial_off)
        result["spatial"] = str(spatial_path)
    json_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    if args.delete_raw:
        args.raw.unlink()
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
