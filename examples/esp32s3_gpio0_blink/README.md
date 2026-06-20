# GPIO0 blink — a bare-metal Ada peripheral driver (ESP32-S3, no FreeRTOS)

Toggles **GPIO0** at 2 Hz from an Ada task, with the GPIO driver written
**directly against the ESP32-S3 registers** — no ESP-IDF, no HAL. This is the
template for writing peripheral drivers in Ada on top of the Ada runtime.

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

> GPIO0 is a strapping / BOOT pin: it is only *sampled* at reset, so driving it
> as an output afterward is safe and does not affect boot. (On dev boards it is
> often the BOOT button; the demo still drives the pad.)

## How it works (`src/gpio.adb`)

The whole driver is ~50 lines of Ada. ESP32-S3 registers are mapped as
address-located volatile words and driven directly:

| Register | Address | Use |
|---|---|---|
| `IO_MUX_GPIO0` | `0x6000_9004` | pad function = GPIO matrix, push-pull, 20 mA |
| `GPIO_FUNC0_OUT_SEL_CFG` | `0x6000_4554` | drive pad 0 from `GPIO_OUT` bit 0 (value 256) |
| `GPIO_ENABLE_W1TS` | `0x6000_4024` | enable the GPIO0 output driver |
| `GPIO_OUT_W1TS` / `_W1TC` | `0x6000_4008` / `…400C` | set / clear GPIO0 (atomic, no read-modify-write) |

A library-level task pinned to core 0 (`CPU => 1`) configures the pin once, then
`delay until`-toggles it every 250 ms. The pattern generalizes: add more pins by
mapping the corresponding bits/registers.

## Build & flash

```sh
. "$IDF_PATH/export.sh"
idf.py -p /dev/ttyACM0 flash monitor
```

The Ada is built against the pinned `esp32s3_rts` crate by
`main/build_ada.sh`. The boot glue (`main/glue.c`) is the standard FreeRTOS-free
takeover (core 0 via `--wrap`, core 1 reset into the runtime); `native_gpio_log`
just echoes the level to the console — the actual register access is in Ada.
