#!/bin/bash
# PIE SIMD benchmark.  Needs the embedded profile (exceptions + Ada 2022 contracts);
# the big aligned vectors live on the env-task stack, so give it some room.
HERE="$(cd "$(dirname "$0")" && pwd)"
export ESP32S3_RTS_PROFILE=embedded
export ENV_STACK_SIZE=131072
exec bash "$HERE/../common/bare/bare_build.sh" "$HERE" "_ada_main"
