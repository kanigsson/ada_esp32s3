# W25Q256FV — a bare-metal Ada SPI NOR flash driver (ESP32-S3, no FreeRTOS)

Bring-up for the reusable **`ESP32S3.W25Q`** Winbond SPI NOR flash driver (in
`libs/esp32s3_hal`) — no ESP-IDF, no FreeRTOS, on the Ada runtime. It identifies
a **W25Q256FV** (32 MB / 256 Mbit), puts it in 4-byte address mode, then does a
full **erase → page-program → read-back** round-trip on a scratch sector.

```
[w25q] bare-metal Winbond SPI-NOR bring-up (SPI2, CS=IO21)
[w25q] JEDEC ID: ef 40 19   (W25Q256FV)  PASS
[w25q] 4-byte address mode: OK
[w25q] after erase: ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff   PASS
[w25q] read-back:  a5 5a f0 0f 11 22 33 44 55 66 77 88 99 aa bb cc   PASS
[w25q] done.
```

## What it checks

1. **JEDEC ID** (`0x9F`) reads `EF 40 19` — Winbond, 0x40, 256 Mbit.
2. **4-byte address mode** (`0xB7`): a 32 MB part needs 4 address bytes to reach
   past 16 MB. `Initialize` sets the mode and confirms status register 3 reports
   `ADS = 1`.
3. **Erase** a 4 KB sector (`0x20`, Write-Enable + busy-poll) and confirm it
   reads back all `0xFF`.
4. **Page-program** a 16-byte pattern (`0x02`) and read it back byte for byte.

This **erases and writes** one scratch sector, 1 MB into the chip. Safe here:
the flash is dedicated to this experiment and holds no filesystem yet.

## Two devices on one bus — the application chip select

The flash shares **SPI2** with the W5500 Ethernet chip. The W5500 uses the
host's single hardware `CS0` (on IO39); the flash brings its **own** select on
**IO21**, driven through the SPI driver's application chip-select callback
(`ESP32S3.SPI.CS_Select`). The driver suppresses the peripheral's hardware `CS0`
while a callback device holds the bus, so the two never collide. For the common
single-GPIO case the driver ships a ready-made callback (`W25Q.GPIO_Select` +
`Pin_Cell`); a decoder or I/O-expander select can supply its own.

## Why the standard opcodes in 4-byte mode (not `0x12`/`0x21`)

The W25Q256**FV** defines **no** dedicated 4-byte program/erase opcodes — its
Instruction Set Table 3 keeps Page Program at `0x02`, Sector Erase at `0x20` and
Block Erase at `0xD8`, which simply take 4 address bytes once the chip is in
4-byte mode. (The `0x12`/`0x21`/`0xDC` set is a later W25Q256**JV** addition; on
the FV those are silently ignored.) Only the *read* family has 4-byte-address
variants such as `0x13`.

## Hardware

| Signal | Pin | Notes |
|---|---|---|
| SCLK | GPIO1 | shared SPI2 bus |
| MOSI | GPIO4 | shared SPI2 bus |
| MISO | GPIO45 | shared SPI2 bus |
| CS | GPIO21 | flash-only, active-low, software-driven |

3V3 / GND to the flash. With nothing wired the JEDEC read returns `00`/`FF` and
the example prints the `FAIL` line, then stops cleanly.

## Build & run

```
./x run esp32s3_w25q          # build + flash + the report prints over USB-Serial-JTAG
```
