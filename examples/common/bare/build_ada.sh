#!/bin/bash
# Build one example's Ada (its single *.gpr) against the pinned esp32s3_rts runtime
# into a relocatable obj/app_main.o for the bare-boot link.  Shared by every example
# and invoked by bare_build.sh as `build_ada.sh <example-dir>`, so examples no longer
# carry a per-project copy or a main/ directory.
set -e
EX="$(cd "${1:?usage: build_ada.sh <example-dir>}" && pwd)"
BARE="$(cd "$(dirname "$0")" && pwd)"         # examples/common/bare
REPO="$(cd "$BARE/../../.." && pwd)"          # repo root
RTCRATE="$REPO/crates/esp32s3_rts"
DYNDIR="$REPO/crates/xtensa-dynconfig"
DYNCFG="$DYNDIR/xtensa-dynconfig/xtensa_esp32s3.so"
. "$REPO/tools/sdk-env.sh"                     # toolchain on PATH, Alire-free
esp32s3_toolchain_on_path
esp32s3_build_dynconfig "$DYNDIR" "$DYNCFG"
export XTENSA_GNU_CONFIG="$(realpath "$DYNCFG")"
export GPR_PROJECT_PATH="$RTCRATE${GPR_PROJECT_PATH:+:$GPR_PROJECT_PATH}"
bash "$RTCRATE/gen_runtime.sh"

# Exactly one project file per example dir; find it rather than hard-code the name.
shopt -s nullglob
GPRS=( "$EX"/*.gpr )
if [ "${#GPRS[@]}" -ne 1 ]; then
    echo "[build_ada] expected exactly one .gpr in $EX, found ${#GPRS[@]}" >&2
    exit 1
fi

( cd "$EX" && gprbuild -p -P "$(basename "${GPRS[0]}")" )
cp "$EX/obj/ada_app.o" "$EX/obj/app_main.o"
echo "[build_ada] done: $EX/obj/app_main.o"
