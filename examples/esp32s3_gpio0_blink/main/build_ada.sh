#!/bin/bash
# Build the GPIO0-blink Ada (gpio_blink.gpr) against the PINNED crate runtime into a
# relocatable app_main.o that the ESP-IDF image links.  Same runtime crate the
# Alire examples consume (crates/esp32s3_rts).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"        # main/
EX="$(cd "$HERE/.." && pwd)"                 # examples/esp32s3_gpio0_blink/
REPO="$(cd "$EX/../.." && pwd)"              # repo root
RTCRATE="$REPO/crates/esp32s3_rts"
DYNDIR="$REPO/crates/xtensa-dynconfig"
DYNCFG="$DYNDIR/xtensa-dynconfig/xtensa_esp32s3.so"


. "$REPO/tools/sdk-env.sh"
esp32s3_toolchain_on_path
esp32s3_build_dynconfig "$DYNDIR" "$DYNCFG"
export XTENSA_GNU_CONFIG="$(realpath "$DYNCFG")"

# Generate the crate runtime (idempotent) and build the skeleton against it.
# gprbuild is invoked directly (not via alr), so make the runtime crate's
# project file (esp32s3_rts.gpr) findable.
export GPR_PROJECT_PATH="$RTCRATE${GPR_PROJECT_PATH:+:$GPR_PROJECT_PATH}"
bash "$RTCRATE/gen_runtime.sh"
( cd "$EX" && gprbuild -p -P gpio_blink.gpr )
cp "$EX/obj/ada_app.o" "$HERE/app_main.o"
echo "[build_ada] done: $HERE/app_main.o"
