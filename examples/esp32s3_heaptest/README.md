# Heap allocator stress — on-target malloc/free — bare-metal Ada (ESP32-S3)

Exercises the **Ada TLSF allocator** (`Tlsf_Core`) that backs the live
`malloc`/`free` symbols, over the **real heap**, on hardware. It runs 50 000
random `malloc`/`free` operations (sizes 1–256 B, up to 32 live blocks), writes a
unique byte pattern into each allocation and re-checks it before freeing — so any
overlap, stale pointer or corruption is caught — then reports `PASS`/`FAIL` via
`ESP32S3.Log`.

```
[heap] on-target malloc/free stress (Ada Tlsf allocator)
[heap] allocs=25010  corruption=0  PASS
```

## DRAM vs PSRAM

By default the heap is the leftover internal **DRAM**. Build with `HEAP_PSRAM=1`
to put the arena in the bootloader-mapped **PSRAM** at `0x3D000000` instead (the
scenario TLSF's O(1) behaviour is for — a large heap where the old first-fit
list's O(n) scan + full-list coalesce would fall over):

```
./build.sh                 # DRAM heap
HEAP_PSRAM=1 ./build.sh    # PSRAM heap (needs PSRAM on the board)
./flash.sh /dev/ttyACM0
```

## How the allocator is wired

`malloc`/`free`/`realloc`/`calloc` are **Ada** (`boot/bare_heap.adb` over
`boot/tlsf_core.adb`), replacing the old C `bare_heap.c`. The Ada is
arena-agnostic — the linker `--defsym`s `__bare_heap_base`/`__bare_heap_end` to
the DRAM or PSRAM region. The same `Tlsf_Core` is also exercised on the host by
`common/bare/boot/test/run.sh`. See `freestanding-libc` notes for the boot
gotcha that made this tricky: an elaborated header-size constant in a ZFP boot
unit (no `adainit`) had to be made compile-time static.
