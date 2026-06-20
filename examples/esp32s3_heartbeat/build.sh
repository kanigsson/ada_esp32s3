#!/bin/bash
# IDF-free build of esp32s3_heartbeat via the shared bare-boot (examples/common/bare).
# No ESP-IDF / idf.py.  Main unit is "Example" -> _ada_example.
HERE="$(cd "$(dirname "$0")" && pwd)"
exec bash "$HERE/../common/bare/bare_build.sh" "$HERE" "_ada_example"
