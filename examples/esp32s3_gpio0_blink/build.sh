#!/bin/bash
# IDF-free build of gpio0_blink via the shared bare-boot (examples/common/bare).
# No ESP-IDF / idf.py.  Main unit is "Main" -> _ada_main.
HERE="$(cd "$(dirname "$0")" && pwd)"
exec bash "$HERE/../common/bare/bare_build.sh" "$HERE" "_ada_main"
