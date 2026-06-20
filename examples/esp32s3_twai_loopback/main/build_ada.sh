#!/bin/bash
# Build the TWAI Ada (twai_loopback.gpr) against the PINNED crate runtime into a
# relocatable app_main.o that the bootloader's image links.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"        # main/
EX="$(cd "$HERE/.." && pwd)"                 # examples/esp32s3_twai_loopback/
REPO="$(cd "$EX/../.." && pwd)"              # repo root
RTCRATE="$REPO/crates/esp32s3_rts"
DYNDIR="$REPO/crates/xtensa-dynconfig"
DYNCFG="$DYNDIR/xtensa-dynconfig/xtensa_esp32s3.so"

GNAT="$(ls -d "$HOME"/.local/share/alire/toolchains/gnat_xtensa_esp32_elf_*/bin 2>/dev/null | sort -V | tail -1)"
GPR="$(ls -d "$HOME"/.local/share/alire/toolchains/gprbuild_*/bin 2>/dev/null | sort -V | tail -1)"
export PATH="$GPR:$GNAT:$PATH"

[ -f "$DYNCFG" ] || alr -C "$DYNDIR" build
export XTENSA_GNU_CONFIG="$(realpath "$DYNCFG")"
export ESP32S3_RTS_PROFILE="${ESP32S3_RTS_PROFILE:-embedded}"

export GPR_PROJECT_PATH="$RTCRATE${GPR_PROJECT_PATH:+:$GPR_PROJECT_PATH}"
bash "$RTCRATE/gen_runtime.sh"
( cd "$EX" && gprbuild -p -P twai_loopback.gpr )
cp "$EX/obj/ada_app.o" "$HERE/app_main.o"
echo "[build_ada] done: $HERE/app_main.o"
