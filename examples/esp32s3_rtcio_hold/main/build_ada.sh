#!/bin/bash
# Build the RTCIO Ada (rtcio_hold.gpr) against the PINNED crate runtime into a
# relocatable app_main.o that the bootloader's image links.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"        # main/
EX="$(cd "$HERE/.." && pwd)"                 # examples/esp32s3_rtcio_hold/
REPO="$(cd "$EX/../.." && pwd)"              # repo root
RTCIORATE="$REPO/crates/esp32s3_rts"
DYNDIR="$REPO/crates/xtensa-dynconfig"
DYNCFG="$DYNDIR/xtensa-dynconfig/xtensa_esp32s3.so"


. "$REPO/tools/sdk-env.sh"
esp32s3_toolchain_on_path
esp32s3_build_dynconfig "$DYNDIR" "$DYNCFG"
export XTENSA_GNU_CONFIG="$(realpath "$DYNCFG")"
export ESP32S3_RTS_PROFILE="${ESP32S3_RTS_PROFILE:-embedded}"

export GPR_PROJECT_PATH="$RTCIORATE${GPR_PROJECT_PATH:+:$GPR_PROJECT_PATH}"
bash "$RTCIORATE/gen_runtime.sh"
( cd "$EX" && gprbuild -p -P rtcio_hold.gpr )
cp "$EX/obj/ada_app.o" "$HERE/app_main.o"
echo "[build_ada] done: $HERE/app_main.o"
