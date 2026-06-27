# W25Q256FV — a bare-metal Ada SPI NOR flash driver (ESP32-S3, no FreeRTOS)

Bring-up for the reusable **`ESP32S3.W25Q`** Winbond SPI NOR flash driver (in
`libs/esp32s3_hal`) — no ESP-IDF, no FreeRTOS, on the Ada runtime. It identifies
a **W25Q256FV** (32 MB / 256 Mbit), puts it in 4-byte address mode, does a full
**erase → page-program → read-back** round-trip on a scratch sector, then wraps
the flash as a **512-byte-sector `Block_Dev`** and round-trips a full sector
through the filesystem block interface.

```
[w25q] bare-metal Winbond SPI-NOR bring-up (SPI2, CS=IO21)
[w25q] JEDEC ID: ef 40 19   (W25Q256FV)  PASS
[w25q] 4-byte address mode: OK
[w25q] after erase: ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff   PASS
[w25q] read-back:  a5 5a f0 0f 11 22 33 44 55 66 77 88 99 aa bb cc   PASS
[w25q] blockdev write/read A: PASS
[w25q] blockdev rewrite B (erase RMW): PASS
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
5. **Block device** (`ESP32S3.Block_Dev.W25Q_Source`): present the flash as
   512-byte sectors and round-trip one sector twice. The second write is the
   bit-complement of the first, so it can't be done by clearing bits alone — it
   forces the adapter's **4 KB erase read-modify-write** path. Both pass.

This **erases and writes** scratch areas around 1 MB and 2 MB into the chip.
Safe here: the flash is dedicated to this experiment and holds no filesystem yet.

## The Block_Dev adapter — NOR writes behind a plain Read/Write vtable

`ESP32S3.Block_Dev.W25Q_Source` maps the filesystem's 512-byte sectors directly
onto flash byte addresses (LBA *N* ↔ byte *N* × 512) and hides NOR's
erase-before-write rule:

- **Read** is a plain random read.
- **Write** is **write-through** (durable before it returns, so it works with the
  flush-less `Block_Dev` vtable) and **erase-aware**. Flash programming can only
  clear 1→0 bits, so when the new bytes merely clear bits of what's already there
  (the common case — writing into freshly-erased `0xFF` space) it programs in
  place; otherwise it read-modify-writes the whole 4 KB erase block.

This is the **direct** mapping with **no wear leveling** — a hot 4 KB block is
erased in place on every rewrite. The Option B wear-leveling FTL layers on top of
this next.

## Two devices on one bus — the per-device chip select

The flash shares **SPI2** with the W5500 Ethernet chip. The W5500 uses the
host's single hardware `CS0` (on IO39); the flash brings its **own** select on
**IO21**. For the common single-GPIO case you just name the pin —
`Flash := (Host => SPI2, CS_Pin => 21, others => <>)` — and the SPI driver owns
that GPIO, driving it active-low and holding it asserted across the whole command
(so the streamed read keeps `CS` low across every transfer). The driver suppresses
the peripheral's hardware `CS0` while such a device holds the bus, so the two never
collide. A select that is not one plain GPIO (a 3:8 decoder, an I/O-expander line)
supplies a `CS_CB` callback (`ESP32S3.SPI.CS_Select`) instead.

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
