# Touch — bare-metal Ada capacitive touch (ESP32-S3, no FreeRTOS)

Self-test for the reusable **`ESP32S3.Touch`** capacitive-touch driver (in
`libs/esp32s3_hal`) — no ESP-IDF, no FreeRTOS, on the Ada runtime. It brings up
the touch FSM and reads per-pad capacitance, **with no wiring**.

```
[touch] bare-metal capacitive-touch read self-test (no wiring)
[touch] channel 1 (GPIO1): raw count = 1143549
[touch] channel 3 (GPIO3): raw count = 2612285
[touch] baseline counts non-zero + distinct: PASS
[touch] ch1: baseline=1143549 now=1143549  Touched(baseline)=0 Touched(baseline+200k)=1  PASS
```

## What it checks

The touch FSM scans channels 1 (GPIO1) and 3 (GPIO3), each measuring its pad's
self-capacitance by counting charge/discharge cycles in a fixed window. With
nothing connected, every pad still has some self-capacitance, so each reads a
**stable, non-zero** count — and two different pads read **different** counts.
Non-zero + distinct proves the measuring FSM is actually running and producing
real per-pad measurements on silicon (a charge/discharge slope of 0 would make
the counter read 0, which it doesn't).

Touching a pad raises its capacitance and so its count — that part is interactive
(needs a finger) and isn't part of the automated PASS check, which verifies the
baseline measurement.

The second line exercises **`Touched (Ch, Reference, Margin)`**, a software
threshold on the live `Read` value: against the captured baseline the pad reads
*not touched*, and against a deliberately-shifted reference (`baseline + 200k`,
well past the 50k margin) it reads *touched* — proving the margin comparison. A
finger moves the real count past the margin the same way.

## Using the driver

```ada
with ESP32S3.Touch; use ESP32S3.Touch;

Setup;              -- bring up the FSM (scans enabled channels on the RTC timer)
Enable (1);         -- channel n = GPIO n
N := Read (1);      -- raw count, higher = more capacitance (rises when touched)

Base := Read (1);                    -- capture an untouched baseline
if Touched (1, Base, Margin => 50_000) then ...   -- True once a finger lands
```

14 channels on GPIO1..GPIO14. No finalization, so it works under every runtime
profile.

## Build & flash

```sh
./x run esp32s3_touch_read           # build + flash + monitor
```

Built as the **embedded** profile. The report prints over the USB-Serial-JTAG
console via the ROM `esp_rom_printf` glue in `main/glue.c`.
