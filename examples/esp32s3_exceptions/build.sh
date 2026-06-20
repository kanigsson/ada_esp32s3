#!/bin/bash
# IDF-free build of the exception demo via the shared bare-boot
# (examples/common/bare).  Main unit is "Main" -> _ada_main.  The embedded RTS
# uses exceptions + finalization, so request the freestanding heap and a larger
# env-task stack (the unwinder needs the headroom).
HERE="$(cd "$(dirname "$0")" && pwd)"
export HEAP_SIZE=65536 ENV_STACK_SIZE=65536
exec bash "$HERE/../common/bare/bare_build.sh" "$HERE" "_ada_main"
