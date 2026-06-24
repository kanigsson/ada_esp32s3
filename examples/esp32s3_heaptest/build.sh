#!/bin/bash
# On-target malloc/free stress for the Ada (Tlsf) allocator.  Embedded profile,
# DRAM heap by default; set HEAP_PSRAM=1 to stress the PSRAM arena instead.
HERE="$(cd "$(dirname "$0")" && pwd)"
export ESP32S3_RTS_PROFILE=embedded
export HEAP_SIZE=65536 ENV_STACK_SIZE=65536
exec bash "$HERE/../common/bare/bare_build.sh" "$HERE" "_ada_main"
