# GPIO0 blink — a bare-metal Ada peripheral driver (ESP32-S3, no FreeRTOS)

**What it demonstrates:** toggles **GPIO0** at 2 Hz from an Ada task, driving the
pin through the shared HAL (`ESP32S3.GPIO`, in `libs/esp32s3_hal`) — no ESP-IDF,
no FreeRTOS. This is the minimal template for using the driver library on top of
the Ada runtime.

**Build & run:** `./x run esp32s3_gpio0_blink` (default light-tasking profile).

**Output:** the console prints one line per transition, forever:

```
[C] Ada runtime up on both cores
[gpio0] HIGH
[gpio0] low
[gpio0] HIGH
[gpio0] low
...
```
GPIO0 drives a 250 ms half-period (2 Hz) square wave — observe it on a logic
analyzer / scope, or wire an LED (with a series resistor) from GPIO0 to GND.

**Hardware:** none required — observe GPIO0 on a logic analyzer / scope, or wire
an LED (with a series resistor) from GPIO0 to GND.

> GPIO0 is a strapping / BOOT pin: it is only *sampled* at reset, so driving it
> as an output afterward is safe and does not affect boot. (On dev boards it is
> often the BOOT button; the demo still drives the pad.)

## How it works (`src/gpio.adb`)

The whole example is a handful of lines of Ada. It does **not** poke registers
directly; it drives the pin through the shared HAL (`ESP32S3.GPIO`):

- `ESP32S3.GPIO.Configure (Pin, Output, Drive => Drive_Strong)` — set GPIO0 up
  as a push-pull, strong-drive output.
- `ESP32S3.GPIO.Write (Pin, High)` — set / clear the pad each toggle.

A library-level task pinned to core 0 (`CPU => 1`) configures the pin once, then
`delay until`-toggles it every 250 ms. The pattern generalizes: drive more pins
by giving each its `Pin_Id`.

## Build & flash

```sh
./x run esp32s3_gpio0_blink      # build + flash + monitor
```

`./x build|flash|monitor|clean` run the individual steps. There is no ESP-IDF,
`idf.py`, or FreeRTOS — our own bare-metal 2nd-stage bootloader sets up the
flash-XIP cache/MMU and jumps to `_start`, which selects the 240 MHz PLL and
hands off to the GNARL Ada runtime, which owns **both** cores (FreeRTOS never
runs). Core 0 runs the env task; core 1 is cold-started into the GNARL slave
scheduler.

The Ada is built against the pinned `esp32s3_rts` crate by the shared
`examples/common/bare/build_ada.sh`. There is no C glue in this example — the
pin driving (`ESP32S3.GPIO`) *and* the console logging (`ESP32S3.Log`) are both
in Ada (`src/gpio.adb`).
