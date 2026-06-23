#!/bin/bash
# The pure-Ada ext4 FS uses a heap block cache AND the journal commit allocates a
# transaction buffer (~64 KB); put the heap arena in the 8 MB PSRAM so both fit.
HERE="$(cd "$(dirname "$0")" && pwd)"
export ESP32S3_RTS_PROFILE=embedded
export HEAP_SIZE=1 HEAP_PSRAM=1 ENV_STACK_SIZE=65536
exec bash "$HERE/../common/bare/bare_build.sh" "$HERE" "_ada_main"
