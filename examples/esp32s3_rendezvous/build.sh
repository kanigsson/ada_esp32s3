#!/bin/bash
# IDF-free build of the rendezvous demo via the shared bare-boot
# (examples/common/bare).  No ESP-IDF / idf.py.  Main unit is "Main" -> _ada_main.
# Full Ada tasking (rendezvous: task entries / accept / select) uses exceptions +
# finalization + a heap, and each task's stack comes from that heap, so request a
# generous heap + a large env stack.  The full profile is set by main/build_ada.sh.
HERE="$(cd "$(dirname "$0")" && pwd)"
export HEAP_SIZE=196608 ENV_STACK_SIZE=65536
exec bash "$HERE/../common/bare/bare_build.sh" "$HERE" "_ada_main"
