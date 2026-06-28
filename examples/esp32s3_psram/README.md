# External PSRAM from Ada (ESP32-S3, no FreeRTOS, no ESP-IDF)

Enables the module's **8 MB octal PSRAM** and uses it from Ada: a **1 MB static
byte array** placed in external RAM — no heap, no `malloc`. Demonstrates that
large buffers, which never fit in internal SRAM (~292 KB), live comfortably in
PSRAM on the bare Ada runtime. Built and booted **entirely IDF-free** — the
PSRAM is brought up by our own 2nd-stage bootloader (see
`../common/bare/bootloader/`).

```
[ada-free-boot] octal PSRAM up: rc=0  8 MB
[ada-free-boot] PSRAM mapped @0x3D000000 rc=0
[C] Ada runtime up on both cores
[psram] mapped PSRAM @0x3D000000 rc=0 (bootloader did the bring-up)
[psram] buffer @ 0x3d000000  1048576 bytes  checksum=0x07f80000  (PSRAM)
```
The array's `0x3d000000` address is the external-RAM data range; the checksum is
the expected value (bytes `0..255` repeating, summed), proving the full 1 MB
round-trips through the cache to real PSRAM.

## How it works

The hard part — the octal-PSRAM / MSPI bring-up — runs in the **bootloader**, not
the app. Our IDF-free 2nd-stage bootloader, running from SRAM (so the MSPI
reconfig that crashes an app-side init has no flash-XIP rug), enables the octal
PSRAM and maps it at `0x3D000000` before jumping to the app. Two non-obvious
steps make it work (the full story is in `../common/bare/BOOTLOADER_STAGE0.md`):

1. configure the **octal MSPI pins** (`SPID4-7` + `DQS`) the ROM flash setup
   leaves unwired — without them the chip's mode-register read is corrupted and
   the chip is mis-configured;
2. **force the PSRAM input-sampling din mode** to the value the SPI0 cache read
   needs (the auto-tuner calibrates the SPI1 command path, not the cache path).

**The 1 MB array (`src/big.adb`)** — a plain library-level Ada array placed in
the external-RAM bss section, which `psram.ld` maps to the PSRAM region:
```ada
Buffer : array (0 .. 1024*1024 - 1) of Unsigned_8
  with Linker_Section => ".ext_ram.bss";
```
`Big.Run` fills it, reads it back, checksums it, and reports its address; the app
side (`glue.c`) only re-applies the d-bus cache map after the runtime's
`start.S` re-inits the cache (the bootloader already did the chip bring-up).

**Not for task stacks** — those stay in internal SRAM; PSRAM is unreachable
whenever the cache is disabled (e.g. during flash writes).

## Build & flash (no ESP-IDF, no idf.py)

```sh
./x run psram                                         # build + flash + monitor
```
`./x` is the one command surface (`build|flash|monitor|run`); under the hood it
runs this example's `build.sh` (Ada -> `app.bin`) then `flash.sh`, which flash the
app, our 2nd-stage bootloader, and the partition table over USB. To drive the
underlying scripts directly:

```sh
./build.sh                                            # Ada -> app.bin, no idf.py
./flash.sh /dev/ttyACM0                               # bootloader + partitions + app.bin
```
Only the Alire GNAT toolchain + `esptool` are needed.
