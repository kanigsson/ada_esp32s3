#!/bin/bash
# Build the example's Ada (comm_demo.gpr) against the PINNED crate runtime into a
# relocatable app_main.o that ESP-IDF links.  Uses the same crate the Alire
# example consumes (crates/esp32s3_rts), proving it boots on HW.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"        # main/
EX="$(cd "$HERE/.." && pwd)"                 # examples/esp32s3_heartbeat/
REPO="$(cd "$EX/../.." && pwd)"              # repo root
RTCRATE="$REPO/crates/esp32s3_rts"
DYNDIR="$REPO/crates/xtensa-dynconfig"
DYNCFG="$DYNDIR/xtensa-dynconfig/xtensa_esp32s3.so"


. "$REPO/tools/sdk-env.sh"
esp32s3_toolchain_on_path
esp32s3_build_dynconfig "$DYNDIR" "$DYNCFG"
export XTENSA_GNU_CONFIG="$(realpath "$DYNCFG")"

# Generate the crate runtime (idempotent) and build the example against it.
# gprbuild is invoked directly (not via alr), so make the runtime crate's
# project file (esp32s3_rts.gpr) findable.
export GPR_PROJECT_PATH="$RTCRATE${GPR_PROJECT_PATH:+:$GPR_PROJECT_PATH}"
bash "$RTCRATE/gen_runtime.sh"
( cd "$EX" && gprbuild -p -P comm_demo.gpr )
cp "$EX/obj/ada_app.o" "$HERE/app_main.o"
echo "[build_ada] done: $HERE/app_main.o"
