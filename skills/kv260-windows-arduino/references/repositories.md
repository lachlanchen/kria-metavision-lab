# Related Repositories Reference

Use this when finding firmware, theory notes, handoff docs, or Windows project context.

## Board Clone Paths

Cloned under `/home/petalinux/Projects`:

| Repo | Board path | Branch | Current clone commit | Remote |
| --- | --- | --- | --- | --- |
| V-SPICE / polarizer | `/home/petalinux/Projects/polarizer` | `main` | `c82ee94` | `git@github.com:lachlanchen/V-SPICE.git` |
| DualLampHI | `/home/petalinux/Projects/DualLampHI` | `main` | `7966bb6` | `git@github.com:lachlanchen/DualLampHI.git` |
| OpenHI3.0 | `/home/petalinux/Projects/OpenHI3.0` | `main` | `140eb3f` | `https://github.com/lachlanchen/OpenHI3.0.git` |
| OpenHI2.0 | `/home/petalinux/Projects/OpenHI2.0` | `main` | `8b4a4fc` | `https://github.com/lachlanchen/OpenHI2.0.git` |

Verify:

```sh
for d in polarizer DualLampHI OpenHI3.0 OpenHI2.0; do
  git -C "/home/petalinux/Projects/$d" status --short --branch
  git -C "/home/petalinux/Projects/$d" remote -v
done
```

## Windows Paths

```text
C:\Users\Administrator\Projects\polarizer
C:\Users\Administrator\Projects\DualLampHI
C:\Users\Administrator\Projects\OpenHI3.0
C:\Users\Administrator\Projects\OpenHI2.0
```

## Important DualLampHI Files

```text
docs/kv260_windows_arduino_handoff_cn.md
firmware/dual_led_direct_timer1/dual_led_direct_timer1.ino
publication/dual_led_uploaded_setup_cn.pdf
publication/dual_led_direct_arduino_timer1_cn.pdf
publication/dual_led_elegant_minimal_wiring_cn.pdf
```

## Purposes

```text
polarizer / V-SPICE
  voltage-coded spectro-polarimetric imaging, optics, LCD/light valve, phase/polarization/spectrum derivations

DualLampHI
  dual-lamp / dual-LED illumination modulation, Arduino firmware, wiring notes, event-camera illumination concepts

OpenHI3.0
  related OpenHI / dual-lamp idea repository for future hyperspectral/event-camera context

OpenHI2.0
  earlier OpenHI / dual-lamp idea repository for historical context
```
