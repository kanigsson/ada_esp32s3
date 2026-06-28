# PCNT — a bare-metal Ada peripheral driver (ESP32-S3, no FreeRTOS)

Self-test for the reusable **`ESP32S3.PCNT`** pulse-counter driver (in
`libs/esp32s3_hal`) — no ESP-IDF, no FreeRTOS, on the Ada runtime. It counts a
known number of edges **with no external wiring**.

```
[pcnt] bare-metal PCNT pulse-counter self-test (no wiring)
[pcnt] count: pulses-driven=100 counted=100  PASS
[pcnt] raii: 4-claimed=y 5th-rejected=y reclaimed=y  PASS
```

## What it checks

GPIO4 is configured as a software-driven output and routed into PCNT unit 0's
input on the **same pad** (the GPIO matrix feeds the pad into the counter — no
wiring). The program drives 100 clean high pulses (holding each level ~20 µs so
the glitch filter passes the edge) and reads the counter back: exactly 100.

The second line exercises the controlled (RAII) `Unit` handle: claim all four
units, confirm a fifth claim is rejected, then — once the handles leave scope, so
`Finalize` pauses and releases each unit — confirm a fresh claim succeeds.

## Using the driver

```ada
with ESP32S3.PCNT; use ESP32S3.PCNT;

declare
   U : Unit;
begin
   Claim     (U, 0);
   Configure (U, Pin => 4);              -- count rising edges (Both_Edges => True for both)
   --  ... pulses arrive ...
   N := Count (U);                        -- signed 16-bit count; Clear/Pause/Resume too
end;                                      -- counter paused + released
```

Four units (`0 .. 3`). Because the `Unit` uses finalization, the driver is
**embedded/full only** (light-tasking forbids `No_Finalization`).

## Build & flash

```sh
./x run esp32s3_pcnt_count           # build + flash + monitor
```

Built as the **embedded** profile. The report prints over the USB-Serial-JTAG
console via the ROM `esp_rom_printf` glue in `glue.c`.
