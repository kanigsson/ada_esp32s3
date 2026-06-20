# SD-over-SPI — bare-metal Ada SD/SDHC card (ESP32-S3, no FreeRTOS)

Self-test for the reusable **`ESP32S3.SD_SPI`** driver (in `libs/esp32s3_hal`) —
no ESP-IDF, no FreeRTOS, on the Ada runtime. It initialises an SD/SDHC card over
SPI and does a **non-destructive** round-trip on one scratch sector.

```
[sd-spi] bare-metal SD-over-SPI self-test (needs a wired card)
[sd-spi] init: OK   card: SDHC/SDXC
[sd-spi] read#1: OK   first bytes = .. .. .. ..
[sd-spi] write-back: OK
[sd-spi] read#2: OK   first bytes = .. .. .. ..
[sd-spi] round-trip (re-read == original): PASS
[sd-spi] done.
```

With **no card wired** it prints `init: No_Card` and stops cleanly — which is what
the in-tree smoke build shows (the boot + driver path runs on silicon; the PASS
line needs a real card).

## Wiring

A cheap micro-SD breakout (or a bare card holder) on any four free GPIOs + 3V3:

| SD pin | signal | default GPIO |
|--------|--------|--------------|
| CLK    | SCLK   | **GPIO12**   |
| CMD/DI | MOSI   | **GPIO11**   |
| DAT0/DO| MISO   | **GPIO13**   |
| CD/DAT3| CS     | **GPIO10**   |
| VDD    | 3V3    | 3V3          |
| VSS    | GND    | GND          |

A 10 kΩ pull-up on MISO/DO is recommended. Edit the pins at the top of
`src/main.adb` to match your board.

## What it checks

The card is initialised at ≤400 kHz (CMD0 → CMD8 → ACMD41 → CMD58), the driver
switches to the data clock (default 8 MHz), then it **reads** sector `0x2000`,
**writes the very same bytes back**, and **reads again** — the re-read must equal
the original. Because the bytes written are exactly what was just read, the test
loses no card data and is safe to run on a card with a filesystem.

## Using the driver

```ada
with ESP32S3.SD_SPI; with ESP32S3.SPI;

C  : ESP32S3.SD_SPI.Card;
St : ESP32S3.SD_SPI.Status;
B  : ESP32S3.SD_SPI.Block;          --  512 bytes

ESP32S3.SD_SPI.Setup (C, ESP32S3.SPI.SPI2, Sclk => 12, Mosi => 11,
                      Miso => 13, Cs => 10);
ESP32S3.SD_SPI.Initialize (C, St);
ESP32S3.SD_SPI.Read_Block  (C, LBA => 0, Data => B, Result => St);
ESP32S3.SD_SPI.Write_Block (C, LBA => 0, Data => B, Result => St);
```

Every operation takes the SPI host's `Session`, so concurrent callers serialise.
Uses finalization (via that Session) → **embedded / full** profiles only.

## Concurrency

Each public operation (`Initialize` / `Read_Block` / `Write_Block`) acquires the
underlying SPI host's `Session` as its first act and releases it as its last, so
the **whole** CS-low → command → response → data → CS-high transaction is atomic:
a second task calling the same card suspends until the first finishes (and the
controlled `Session` releases the host even on an early return or exception, so the
lock can't leak). Protection is per **SPI host** — two cards on SPI2 and SPI3 run
concurrently and safely (separate guards, separate per-host DMA buffers). Note the
lock is held across the whole block transfer, so there is no concurrency *during* a
transfer. As always, the lock keeps the hardware consistent; coordinating *which*
task writes *what* (e.g. two tasks targeting one sector) is still the app's job.

`Setup` is **not** locked — call it once at startup, single-threaded, before any
task contends for the card.

## Build & flash

```sh
./x run esp32s3_sd_spi           # build + flash + monitor
```

Built as the **embedded** profile. The report prints over the USB-Serial-JTAG
console via the ROM `esp_rom_printf` glue in `main/glue.c`.
