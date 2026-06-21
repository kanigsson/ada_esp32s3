#!/bin/bash
# Build the TOUCH Ada (touch_read.gpr) against the PINNED crate runtime into a
# relocatable app_main.o that the bootloader's image links.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"        # main/
EX="$(cd "$HERE/.." && pwd)"                 # examples/esp32s3_touch_read/
REPO="$(cd "$EX/../.." && pwd)"              # repo root
TOUCHRATE="$REPO/crates/esp32s3_rts"
DYNDIR="$REPO/crates/xtensa-dynconfig"
DYNCFG="$DYNDIR/xtensa-dynconfig/xtensa_esp32s3.so"


. "$REPO/tools/sdk-env.sh"
esp32s3_toolchain_on_path
esp32s3_build_dynconfig "$DYNDIR" "$DYNCFG"
export XTENSA_GNU_CONFIG="$(realpath "$DYNCFG")"
export ESP32S3_RTS_PROFILE="${ESP32S3_RTS_PROFILE:-embedded}"

export GPR_PROJECT_PATH="$TOUCHRATE${GPR_PROJECT_PATH:+:$GPR_PROJECT_PATH}"
bash "$TOUCHRATE/gen_runtime.sh"
( cd "$EX" && gprbuild -p -P touch_read.gpr )
cp "$EX/obj/ada_app.o" "$HERE/app_main.o"
echo "[build_ada] done: $HERE/app_main.o"
