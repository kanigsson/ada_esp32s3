#!/bin/bash
# IDF-free build of the PSRAM demo via the shared bare-boot (examples/common/bare).
# No ESP-IDF / idf.py.  Main unit is "Main" -> _ada_main.  Brings up the external
# octal PSRAM with the IDF's vendored octal-PSRAM + MSPI-timing objects
# (vendor_psram/, copied from this example's idf.py build/) + a few leaf stubs
# (main/glue.c), and maps it for big.adb's 1 MB .ext_ram.bss array (psram.ld).
# No HEAP_SIZE: this is light-tasking (no heap), and its runtime already provides
# memcpy -- the few other mem*/abort the PSRAM objects need are in main/glue.c.
HERE="$(cd "$(dirname "$0")" && pwd)"
export ENV_STACK_SIZE=98304            # the MSPI timing tuning puts big reference buffers on the env stack
export EXTRA_OBJS="$(echo "$HERE"/vendor_psram/*.obj)"
export EXTRA_LD="$HERE/psram.ld"
exec bash "$HERE/../common/bare/bare_build.sh" "$HERE" "_ada_main"
