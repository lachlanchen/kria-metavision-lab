# Windows Arduino Control Reference

Use this when working with Arduino CLI, serial light commands, or the future Windows Arduino API.

## Physical Reality

The Arduino UNO is attached to Windows by USB serial. It has no IP address.

Correct path:

```text
KV260 or Windows controller -> Windows host -> Arduino COM port -> LEDs
```

## Known Arduino State

```text
Board: Arduino UNO
FQBN: arduino:avr:uno
previous port: COM3
problem noted by Windows: only COM1 Unknown currently detected
```

Before controlled experiments:

```powershell
arduino-cli board list
```

Expected:

```text
COM3 ... Arduino UNO ... arduino:avr:uno
```

If only `COM1 Unknown` appears, fix USB cable, port, driver, or serial-port ownership before trying KV260 control.

## Arduino CLI Use

Use `arduino-cli` for firmware operations:

```powershell
arduino-cli version --json
arduino-cli config init
arduino-cli core update-index
arduino-cli board list --json
arduino-cli core install arduino:avr
arduino-cli compile --fqbn arduino:avr:uno C:\path\to\LightController
arduino-cli upload -p COM3 --fqbn arduino:avr:uno C:\path\to\LightController
```

Do not use `arduino-cli monitor` as the main runtime command API. Use direct serial I/O (`pyserial`, .NET `SerialPort`, etc.) for light commands.

## Current DualLampHI Sketch

Board clone path:

```text
/home/petalinux/Projects/DualLampHI/firmware/dual_led_direct_timer1/dual_led_direct_timer1.ino
```

Windows path:

```text
C:\Users\Administrator\Projects\DualLampHI\firmware\dual_led_direct_timer1\dual_led_direct_timer1.ino
```

Known behavior:

```text
D9  -> LED A
D10 -> LED B
LED A: dark -> bright -> dark
LED B: bright -> dark -> bright
frequency: about 0.5 Hz
cycle: about 2 seconds
PWM carrier: about 62.5 kHz using Timer1
```

## Recommended Runtime Protocol

Future serial-command sketch should accept newline-delimited commands:

```text
PING
ON
OFF
PWM 0..255
PULSE <on_ms> <off_ms> <count>
STATUS
```

Expected responses:

```text
OK <command>
ERR <reason>
STATE light=<0|1> pwm=<0..255>
```

## Windows Arduino API

Recommended local Windows API:

```text
http://127.0.0.1:8780
```

Recommended LAN URL from KV260:

```text
http://192.168.1.166:8780
```

Core endpoints:

```text
GET  /api/v1/arduino/status
GET  /api/v1/arduino/boards
POST /api/v1/arduino/core/install
POST /api/v1/arduino/sketch/compile
POST /api/v1/arduino/sketch/upload
POST /api/v1/arduino/serial/connect
POST /api/v1/arduino/serial/command
POST /api/v1/light/on
POST /api/v1/light/off
POST /api/v1/light/pwm
POST /api/v1/experiment/run
```

If KV260 calls this API directly, Windows firewall must allow inbound TCP `8780`.

## Bootloader Burn

Bootloader burn is advanced, not normal upload.

Require:

```text
explicit programmer
exact command display
confirmation text
log file
```

Example only:

```powershell
arduino-cli burn-bootloader -b arduino:avr:uno -P atmel_ice
```
