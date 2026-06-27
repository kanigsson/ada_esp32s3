# PCF85063A RTC — a bare-metal Ada device driver (ESP32-S3, no FreeRTOS)

Demo for the reusable **`ESP32S3.PCF85063A`** real-time-clock driver (in
`libs/esp32s3_hal`) — no ESP-IDF, no FreeRTOS, on the Ada runtime. It layers the
NXP PCF85063A's register protocol over the task-safe **`ESP32S3.I2C`** master and
drives a real chip on the bus, then arms a seconds-match alarm wired to a GPIO
interrupt.

```
[rtc] PCF85063A RTC driver demo (SDA=IO8  SCL=IO7  INT=none)
[rtc] probe     : OK
[rtc] reset     : OK
[rtc] set-time  : OK
[rtc] Mon 2026-06-22 14:30:00  (integrity OK)
[rtc] set-alarm : OK
[rtc] Mon 2026-06-22 14:30:01  (integrity OK)
[rtc] Mon 2026-06-22 14:30:02  (integrity OK)
[rtc] Mon 2026-06-22 14:30:03  (integrity OK)
[rtc] Mon 2026-06-22 14:30:04  (integrity OK)
[rtc] Mon 2026-06-22 14:30:05  (integrity OK)
[rtc] *** ALARM fired ***  (detected via I2C poll)
[rtc] done.
```

## Wiring

| PCF85063A | ESP32-S3 | notes |
|---|---|---|
| SDA | **IO8** | I2C0 data — internal pull-up enabled for bring-up |
| SCL | **IO7** | I2C0 clock — internal pull-up enabled for bring-up |
| INT | *not wired* | this board has no INT connection — see `Int_Pin` below |
| VDD / VSS | 3V3 / GND | |

Add real bus pull-ups (e.g. 4.7 kΩ to 3V3 on SDA/SCL) for anything beyond a
quick bench bring-up; the internal pulls are weak.

## What it does

| step | driver call | proves |
|---|---|---|
| `probe` | `Get_Time` | the chip ACKs its fixed `0x51` address (else `no device`) |
| `reset` | `Reset` | software reset to a known register state |
| `set-time` | `Set_Time` | BCD calendar write; writing seconds clears the oscillator-stop (OS) flag, so the clock reads back with **integrity OK** |
| `set-alarm` | `Set_Alarm` | a seconds-match alarm 5 s out, with the alarm interrupt (and INT output) enabled |
| `watch` | `Get_Time` / `Alarm_Triggered` | the time increments once a second; when the alarm flag latches, the run reports it and `Acknowledge_Alarm` releases INT |

The driver hard-codes no pins: the wiring is stated in `src/main.adb`
(`Rtc_Sda`, `Rtc_Scl`, `Rtc_Int`) and handed to `Setup`, which records it in the
`Device`. Each operation then opens a short-lived `ESP32S3.I2C` `Session` that
auto-releases the host on scope exit (finalization), so transactions serialise
and a fault can't leak the bus.

This board has **no INT line wired**, so `Rtc_Int` is `ESP32S3.GPIO.No_Pin`: the
alarm is found by polling the alarm flag (`AF`) over I2C (`detected via I2C
poll`), and `ESP32S3.PCF85063A.Interrupts.Attach (Dev, …)` is a no-op.

To use a hardware interrupt instead, set `Rtc_Int` to the GPIO the INT line is
wired to. `Setup` stores it, and `Attach` arms it on that pin (falling-edge,
internal pull-up — INT is active-low, open-drain). That ISR runs in interrupt
context, so it only latches an `Atomic` flag (`src/alarm_irq.adb`) and the main
task does the I2C work; the report then reads `detected via INT interrupt`.

## Build / flash / run

```sh
./x build pcf85063a            # -> app.bin (embedded profile)
./x flash pcf85063a -p /dev/ttyACM0
./x run   pcf85063a -p /dev/ttyACM0    # build + flash + serial monitor (115200)
```

Console output goes through the ROM USB-Serial-JTAG `printf` (the
example-specific glue in `glue.c`); the Ada driver does all the I2C and
register work. If you see `no PCF85063A ACK at 0x51`, check power and the
SDA/SCL wiring.

## Notes

- The PCF85063**A** has no century bit (unlike the PCF8563), so the driver
  anchors the 2-digit year to **2000–2099** and runs the chip in **24-hour** mode.
- Day-of-week is a free 0–6 counter in the chip; the `Weekday` enum (0 = Sunday)
  is the driver's convention — the hardware does not interpret it.
- This driver uses the controlled I2C `Session` (finalization), so like the other
  Session drivers it targets the **embedded / full** profiles, not light-tasking.
