#!/bin/bash
# IDF-free build of the PSRAM demo via the shared bare-boot (examples/common/bare).
# No ESP-IDF / idf.py.  Main unit is "Main" -> _ada_main.  Brings up the external
# octal PSRAM with the IDF's vendored octal-PSRAM + MSPI-timing objects
# (vendor_psram/, copied from this example's idf.py build/) + a few leaf stubs
# (main/glue.c), and maps it for big.adb's 1 MB .ext_ram.bss array (psram.ld).
# No HEAP_SIZE: this is light-tasking (no heap), and its runtime already provides
# memcpy -- the few other mem*/abort the PSRAM objects need are in main/glue.c.
HERE="$(cd "$(dirname "$0")" && pwd)"
export ENV_STACK_SIZE=98304            # generous env stack (kept; the app itself is light)
# No EXTRA_OBJS: the app does NOT bring up PSRAM (glue.c PSRAM_ENABLE=0 -- the 2nd-stage
# bootloader does it).  It only maps PSRAM via ROM Cache_Dbus_MMU_Set, so it needs none of
# the vendored octal-PSRAM / mspi_timing objects.
export EXTRA_LD="$HERE/psram.ld"
exec bash "$HERE/../common/bare/bare_build.sh" "$HERE" "_ada_main"
