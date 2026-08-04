#!/usr/bin/env python3
"""Decode a PSE2/EVT2.1 RAW file into reproducible event-rate statistics."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
import numpy as np

WIDTH = 1280
HEIGHT = 720
POPCOUNT8 = np.array([bin(value).count(chr(49)) for value in range(256)], dtype=np.uint8)


def decode_bins(path: Path, bin_us: int) -> dict:
    timestamps_all, counts_all, polarity_all = [], [], []
    current_high = np.uint64(0)
    base_time_set = False
    words_total = 0
    words_without_timebase = 0
    with path.open("rb") as handle:
        while True:
            payload = handle.read(2_000_000 * 8)
            usable = len(payload) - len(payload) % 8
            if usable <= 0:
                break
            words = np.frombuffer(payload[:usable], dtype="<u8")
            words_total += words.size
            kind = (words >> np.uint64(60)) & np.uint64(0xF)
            is_high = kind == np.uint64(8)
            if np.any(is_high):
                high = (((words >> np.uint64(32)) & np.uint64(0x0FFFFFFF))
                        << np.uint64(6))
                high_at = np.where(is_high, np.arange(words.size), -1)
                last_high = np.maximum.accumulate(high_at)
                base = np.full(words.size, current_high, dtype=np.uint64)
                seen = last_high >= 0
                base[seen] = high[last_high[seen]]
                current_high = np.uint64(high[np.flatnonzero(is_high)[-1]])
                time_valid = seen | base_time_set
                base_time_set = True
            else:
                base = np.full(words.size, current_high, dtype=np.uint64)
                time_valid = np.full(words.size, base_time_set, dtype=bool)
            raw_cd = (kind == 0) | (kind == 1)
            words_without_timebase += int(np.count_nonzero(raw_cd & ~time_valid))
            cd = raw_cd & time_valid
            if not np.any(cd):
                continue
            cd_words = words[cd]
            x = ((cd_words >> np.uint64(43)) & np.uint64(0x7FF)).astype(np.int32)
            y = ((cd_words >> np.uint64(32)) & np.uint64(0x7FF)).astype(np.int32)
            vectors = (cd_words & np.uint64(0xFFFFFFFF)).astype(np.uint32)
            valid = (x < WIDTH) & (y < HEIGHT) & (vectors != 0)
            if not np.any(valid):
                continue
            vectors = vectors[valid]
            counts = np.sum(
                POPCOUNT8[vectors.view(np.uint8).reshape(-1, 4)], axis=1
            ).astype(np.int32)
            timestamps = (
                base[cd][valid]
                + ((cd_words[valid] >> np.uint64(54)) & np.uint64(0x3F))
            ).astype(np.int64)
            timestamps_all.append(timestamps)
            counts_all.append(counts)
            polarity_all.append(kind[cd][valid] == 1)
    if not timestamps_all:
        raise RuntimeError("recording contains no timestamped CD events")
    timestamps = np.concatenate(timestamps_all)
    counts = np.concatenate(counts_all)
    polarity = np.concatenate(polarity_all)
    origin = int(np.min(timestamps))
    bins = ((timestamps - origin) // bin_us).astype(np.int64)
    size = int(np.max(bins)) + 1
    on = np.bincount(bins[polarity], weights=counts[polarity], minlength=size)
    off = np.bincount(bins[~polarity], weights=counts[~polarity], minlength=size)
    return {
        "on": on.astype(float), "off": off.astype(float), "origin_us": origin,
        "span_us": int(np.max(timestamps)) - origin, "words_total": int(words_total),
        "words_without_timebase": int(words_without_timebase),
    }


def frequency_peaks(total: np.ndarray, bin_us: int) -> list:
    if len(total) < 64:
        return []
    width = max(3, int(round(0.20 * 1e6 / bin_us)) | 1)
    trend = np.convolve(total, np.ones(width) / width, mode="same")
    spectrum = np.abs(np.fft.rfft((total - trend) * np.hanning(len(total))))
    frequency = np.fft.rfftfreq(len(total), bin_us / 1e6)
    usable = np.flatnonzero((frequency >= 10.0) & (frequency <= min(4000.0, frequency[-1])))
    ranked = usable[np.argsort(spectrum[usable])[::-1]] if usable.size else []
    maximum = max(float(np.max(spectrum[usable])), 1.0) if usable.size else 1.0
    output = []
    for index in ranked:
        value = float(frequency[index])
        if any(abs(value - row["frequency_hz"]) < 1.0 for row in output):
            continue
        output.append({"frequency_hz": value,
                       "relative_amplitude": float(spectrum[index] / maximum)})
        if len(output) == 10:
            break
    return output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("raw", type=Path)
    parser.add_argument("--bin-us", type=int, default=1000)
    parser.add_argument("--output-prefix", type=Path)
    parser.add_argument("--no-csv", action="store_true")
    args = parser.parse_args()
    raw = args.raw.resolve()
    prefix = (args.output_prefix or raw.with_suffix("")).resolve()
    prefix.parent.mkdir(parents=True, exist_ok=True)
    decoded = decode_bins(raw, args.bin_us)
    on, off = decoded["on"], decoded["off"]
    total = on + off
    duration_s = max(decoded["span_us"] / 1e6, args.bin_us / 1e6)
    summary = {
        "source": str(raw), "format": "PSE2/EVT2.1", "bin_us": args.bin_us,
        "timestamp_origin_us": decoded["origin_us"],
        "timestamp_span_s": decoded["span_us"] / 1e6,
        "raw_bytes": raw.stat().st_size, "words_total": decoded["words_total"],
        "cd_words_discarded_before_first_time_high": decoded["words_without_timebase"],
        "on_events": int(np.sum(on)), "off_events": int(np.sum(off)),
        "total_events": int(np.sum(total)),
        "mean_event_rate_eps": float(np.sum(total) / duration_s),
        "p95_bin_event_rate_eps": float(np.percentile(total, 95) * 1e6 / args.bin_us),
        "dominant_frequencies": frequency_peaks(total, args.bin_us),
    }
    np.savez_compressed(str(prefix) + ".event_stats.npz",
                        time_s=np.arange(len(total)) * args.bin_us / 1e6,
                        on=on, off=off, total=total)
    if not args.no_csv:
        with Path(str(prefix) + ".event_stats.csv").open(
            "w", newline="", encoding="utf-8"
        ) as handle:
            writer = csv.writer(handle)
            writer.writerow(["time_s", "on_events", "off_events", "total_events"])
            for index in range(len(total)):
                writer.writerow([f"{index * args.bin_us / 1e6:.9f}",
                                 int(on[index]), int(off[index]), int(total[index])])
    Path(str(prefix) + ".event_stats.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

