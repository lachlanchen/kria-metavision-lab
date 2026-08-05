# Native Metavision Spatial and ROI Scoring

`scripts/kv260-metavision-event-stats.py` retains its original full-frame EVT2.1 time-bin behavior and now optionally supports:

```sh
python3 scripts/kv260-metavision-event-stats.py capture.raw \
  --output-prefix /tmp/result --bin-us 100 --spatial

python3 scripts/kv260-metavision-event-stats.py capture.raw \
  --output-prefix /tmp/result --roi 100,80,900,650
```

EVT2.1 CD words contain a 32-pixel horizontal vector. ROI counts expand its set bits exactly. Spatial diagnostic maps use a vector-weighted center (`x_base + 15`) for speed, with at most 16 pixels horizontal localization uncertainty, and save `*_spatial.npz`.

The August 2026 V-SPICE diagnostic found that the dominant 7.2 ms event bursts span nearly the full 1280×720 field. Source-on spatial maps correlated 0.91–0.98 with all-off, so a compact ROI could not remove this baseline. Scientific compensation therefore reports both total events and a modulation-locked signed `ON-OFF` metric, while camera biases remain unchanged.
