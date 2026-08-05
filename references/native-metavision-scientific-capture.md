# Native Metavision Scientific Capture

Use one persistent native Metavision HAL process for quantitative event-rate
experiments. Repeated direct V4L2 `STREAMOFF`/`STREAMON` operations can leave
the KV260 CSI/VDMA path in a partial state, producing short RAW files that look
quiet because most of the experiment was never recorded.

## Required Runtime

```sh
echo on | sudo tee /sys/class/video4linux/v4l-subdev3/device/power/control
DISPLAY=:0 /usr/bin/metavision_viewer -o /tmp/native-optical-proof.raw
```

Keep this process open across all controls, candidates, and replays. Toggle
recording with:

```sh
DISPLAY=:0 python3 scripts/kv260-metavision-key.py space
```

After stopping a recording, reduce it on the board:

```sh
python3 scripts/kv260-metavision-event-stats.py INPUT.raw \
  --output-prefix /tmp/capture-stats --bin-us 1000
```

Transfer only the compact JSON/CSV outputs. Delete the RAW after the decoder
confirms a valid `EVT21;height=720;width=1280` header and a plausible timestamp
span. Use `metavision_file_info` for independent validation captures.

## Validity Rules

- Keep all six camera biases unchanged during optical comparisons.
- Confirm the official viewer owns `/dev/video0` for the entire experiment.
- Score only the smooth scan window, excluding startup, shutdown, and timing
  marker edges.
- Compare merged illumination against tungsten-only, RGBW-only, and static
  controls acquired in the same native HAL session.
- Reject a capture if new `Stream Line Buffer Full` messages appear.
- Never interpret a tiny or short RAW as optical cancellation.
- Stop recording before deleting the fixed viewer output path.
- Leave all illumination channels OFF after every finite capture.
