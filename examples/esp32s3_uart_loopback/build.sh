#!/bin/bash
# IDF-free build of esp32s3_uart_loopback via the shared bare-boot (examples/common/bare).
# No ESP-IDF / idf.py.  Main unit is "Main" -> _ada_main.
#
# The ESP32S3.* drivers target the EMBEDDED profile (full exception propagation),
# so the -gnata-enabled contracts raise a catchable exception rather than
# resetting.  Embedded uses exceptions + finalization -> request heap + larger stack.
HERE="$(cd "$(dirname "$0")" && pwd)"
export ESP32S3_RTS_PROFILE=embedded
export HEAP_SIZE=65536 ENV_STACK_SIZE=65536
exec bash "$HERE/../common/bare/bare_build.sh" "$HERE" "_ada_main"
