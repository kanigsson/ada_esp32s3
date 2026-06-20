# GDMA — a bare-metal Ada peripheral driver (ESP32-S3, no FreeRTOS)

Self-test for the reusable **`ESP32S3.GDMA`** general-purpose DMA driver (in
`libs/esp32s3_hal`) — no ESP-IDF, no FreeRTOS, on the Ada runtime. It does a
memory-to-memory DMA copy and exercises the **RAII channel handle**, all **with
no external wiring**.

```
[gdma] bare-metal GDMA mem-to-mem + RAII channel self-test
[gdma] mem2mem copy (64 B): PASS
[gdma] raii: 5-claimed=y 6th-rejected=y reclaimed=y  PASS
[gdma] done.
```

## What it checks

**`mem2mem copy`** fills a 64-byte source buffer, claims a channel, runs a
blocking `Copy` to a zeroed destination, and compares byte for byte. This proves
the descriptor engine, the channel crossbar and the (subtle) mem2mem trigger-slot
wiring all work.

**`raii`** is the point of the controlled `Channel` handle. The S3 has five GDMA
channel pairs. The test claims all five in a scope, confirms a **sixth claim is
rejected** (`Is_Valid` is `False` — no channel left), then lets the handles leave
scope. Because `Channel` is `Limited_Controlled`, `Finalize` returns each channel
to the pool on scope exit; a fresh claim afterwards **succeeds** (`reclaimed=y`),
proving the five were released automatically. Being limited, a `Channel` also
cannot be copied — two tasks can't alias one channel or reuse it through a stale
copy.

## Using the driver

```ada
with ESP32S3.GDMA; use ESP32S3.GDMA;

declare
   Ch : Channel;                          -- limited + controlled (RAII handle)
begin
   Claim (Ch, Mem2Mem);                   -- grab one of the 5 channel pairs
   if Is_Valid (Ch) then
      Copy (Ch, Dst'Address, Src'Address, 64);
   end if;
end;                                      -- Finalize releases the channel back to the pool
```

`Claim` fills the handle in place with a free channel (it is a procedure, not a
function, because a limited type can't be returned by value). A channel bound to
a peripheral (`Claim (Ch, SPI2)`) drives one direction at a time with the
lower-level `Start` / `Wait` / `Done` primitives — `ESP32S3.SPI` is the first
such consumer.

Because `Channel` uses finalization, the driver is **embedded/full-only**;
light-tasking (which forbids `No_Finalization`) excludes it.

## Build & flash

```sh
./x run esp32s3_gdma_copy           # build + flash + monitor
# or:
./x build esp32s3_gdma_copy
./x flash esp32s3_gdma_copy -p /dev/ttyACM0
```

Built as the **embedded** profile (the drivers target it). The report prints
over the USB-Serial-JTAG console via the ROM `esp_rom_printf` glue in
`main/glue.c`.
