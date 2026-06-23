# ST7789 SPI display — a bare-metal Ada driver (ESP32-S3)

Demo for the reusable **`ESP32S3.ST7789`** driver (in `libs/esp32s3_hal`) — a
4-wire SPI display controller (ST77xx family), **write-only** (CLK + MOSI, no
MISO), 16-bit RGB565 pixels. Verified on a 240×240 panel at 40 MHz.

```
[lcd] ST7789 240x240 SPI display demo (SPI2 sclk=12 mosi=13 dc=16 cs=10, bl=6)
[lcd] backlight + setup
[lcd] init
[lcd] fill red
[lcd] fill green
[lcd] fill blue
[lcd] colour bars
[lcd] centre box
[lcd] done -- check the panel.
```

The panel is the real output — SPI is write-only, so there's nothing to read
back and the console only narrates the steps. The demo paints solid red →
green → blue, then eight vertical colour bars, then a centred white box with an
orange box inside it, and holds.

## Two-level locking (what this driver is built around)

Like the TCA9555 (and unlike the RTC, whose `Session` *is* the bus lock), the
display separates the two levels so a held display doesn't tie up the SPI bus:

- **`Session`** is an exclusive, RAII hold on **one display**. Hold it across a
  whole sequence of operations so no other task can corrupt the controller
  mid-sequence (a window-then-stream blit must not be interleaved).
- The **SPI host** is locked only *inside* each operation — assert CS, transfer,
  deassert CS, release — so the peripheral is used "only as long as necessary"
  and is free between operations for another task or device. CS is high whenever
  the bus is released, so nothing interferes.

```ada
Acquire (S, LCD);          -- lock THIS display (bus untouched)
  Init (S);                -- briefly lock SPI per command -> release
  Fill (S, Blue);          -- window + stream pixels, locking SPI per chunk
   … bus free for others between transfers …
  Fill_Rect (S, 70, 70, 100, 100, White);
Release (S);               -- unlock display (auto on scope exit)
```

The per-display guards are a fixed library-level array keyed by the **CS pin** (a
GPIO uniquely identifies one display), so no protected object lives in a
`Device`.

## Wiring

| ST7789 | ESP32-S3 | notes |
|---|---|---|
| SCLK | **IO12** | SPI2 clock |
| MOSI / SDA | **IO13** | SPI2 data (write-only) |
| DC | **IO16** | data/command select (driven by the driver) |
| CS | **IO10** | chip select (driven by the driver as a plain GPIO) |
| RST | *not wired* | `RST` defaults to `No_Pin` → software reset (SWRESET) |
| MISO | *n/a* | controller cannot be read back |
| **BLK** (backlight) | **IO6** | **driven by the example, NOT the driver** |

The backlight is deliberately outside the driver: the example drives IO6 high
itself via `ESP32S3.GPIO` before `Setup`. Resolution is set at `Setup`
(`Width`/`Height`, default 240×240); panels needing a controller-to-panel origin
shift can pass `X_Offset`/`Y_Offset` (none needed here).

## Driver surface

`Setup` (wiring + geometry + SPI host/mode/clock), `Acquire`/`Release`, then the
held-`Session` operations: `Init`, `Display_On`/`Display_Off`, `Set_Rotation`,
`Invert`, `Sleep`, `Fill`, `Fill_Rect`, `Set_Pixel`, and `Draw_Bitmap` (blit a
row-major `Color_Array`). Colours are RGB565 — `RGB (r, g, b)` plus
`Black`/`White`/`Red`/`Green`/`Blue` constants.

## Build / flash / run

```sh
./x build st7789            # -> app.bin (embedded profile)
./x flash st7789 -p /dev/ttyACM0
./x run   st7789 -p /dev/ttyACM0
```

## Notes

- Default SPI clock is **40 MHz**; pass `Clock_Hz =>` a lower value to `Setup`
  for long wires or bring-up (1 MHz was used to first verify this panel).
- Uses controlled `Session`s, so like the other Session drivers it targets the
  **embedded / full** profiles, not light-tasking.
