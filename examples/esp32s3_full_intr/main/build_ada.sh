#!/bin/bash
# Build the example's Ada (example.gpr) against the PINNED crate runtime into a
# relocatable app_main.o.  FULL profile (ESP32S3_RTS_PROFILE=full): proves the
# Ada.Interrupts / pragma Attach_Handler protected handlers build against the
# bareboard full System.Interrupts.  (The primary IDF-free path is ../build.sh.)
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"        # main/
EX="$(cd "$HERE/.." && pwd)"                 # examples/esp32s3_full_intr/
REPO="$(cd "$EX/../.." && pwd)"              # repo root
RTCRATE="$REPO/crates/esp32s3_rts"
DYNDIR="$REPO/crates/xtensa-dynconfig"
DYNCFG="$DYNDIR/xtensa-dynconfig/xtensa_esp32s3.so"

GNAT="$(ls -d "$HOME"/.local/share/alire/toolchains/gnat_xtensa_esp32_elf_*/bin 2>/dev/null | sort -V | tail -1)"
GPR="$(ls -d "$HOME"/.local/share/alire/toolchains/gprbuild_*/bin 2>/dev/null | sort -V | tail -1)"
export PATH="$GPR:$GNAT:$PATH"

[ -f "$DYNCFG" ] || alr -C "$DYNDIR" build
export XTENSA_GNU_CONFIG="$(realpath "$DYNCFG")"

# Select the full runtime profile for both RTS generation and the build.
export ESP32S3_RTS_PROFILE=full

# Generate the crate runtime (idempotent) and build the example against it.
export GPR_PROJECT_PATH="$RTCRATE${GPR_PROJECT_PATH:+:$GPR_PROJECT_PATH}"
bash "$RTCRATE/gen_runtime.sh"
( cd "$EX" && gprbuild -p -P example.gpr )
cp "$EX/obj/ada_app.o" "$HERE/app_main.o"
echo "[build_ada] done (full profile): $HERE/app_main.o"
