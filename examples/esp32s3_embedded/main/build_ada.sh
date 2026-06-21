#!/bin/bash
# Build this app's Ada (app.gpr) against the PINNED crate runtime -- selecting
# the EMBEDDED profile (full exceptions + finalization) -- into a relocatable
# app_main.o that the ESP-IDF image links.
#
# The embedded profile differs from the default light-tasking one in: exception
# propagation, exception-name registration and controlled-type finalization.
# It is selected purely by ESP32S3_RTS_PROFILE=embedded, which both gen_runtime.sh
# (which builds the matching RTS and defers -lc/-lgcc to the IDF link) and the
# runtime crate's project file consume.  sdkconfig.defaults additionally sets
# CONFIG_COMPILER_CXX_EXCEPTIONS=y so the IDF link keeps .eh_frame and registers
# the DWARF frames the unwinder needs.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"        # main/
EX="$(cd "$HERE/.." && pwd)"                 # examples/esp32s3_embedded/
REPO="$(cd "$EX/../.." && pwd)"              # repo root
RTCRATE="$REPO/crates/esp32s3_rts"
DYNDIR="$REPO/crates/xtensa-dynconfig"
DYNCFG="$DYNDIR/xtensa-dynconfig/xtensa_esp32s3.so"


. "$REPO/tools/sdk-env.sh"
esp32s3_toolchain_on_path
esp32s3_build_dynconfig "$DYNDIR" "$DYNCFG"
export XTENSA_GNU_CONFIG="$(realpath "$DYNCFG")"

# Select the embedded runtime profile for both the RTS generation and the build.
export ESP32S3_RTS_PROFILE=embedded

# Generate the (embedded) crate runtime (idempotent) and build the app.  gprbuild
# is invoked directly (not via alr), so make the runtime crate's project file
# findable.
export GPR_PROJECT_PATH="$RTCRATE${GPR_PROJECT_PATH:+:$GPR_PROJECT_PATH}"
bash "$RTCRATE/gen_runtime.sh"
( cd "$EX" && gprbuild -p -P app.gpr )
cp "$EX/obj/ada_app.o" "$HERE/app_main.o"

# The runtime's System.Memory exports malloc/calloc/free (+ mem*) for C interop;
# under ESP-IDF those clash with newlib's.  Ada's own `new` path is self-contained
# inside app_main.o (__gnat_malloc -> System.Memory.Alloc over the ada_heap
# region), so localise the C aliases -> newlib keeps the global ones for IDF C.
OBJCOPY=xtensa-esp32-elf-objcopy   # on PATH via tools/sdk-env.sh
for s in malloc calloc free realloc memcpy memset; do LOC="$LOC --localize-symbol=$s"; done
"$OBJCOPY" $LOC "$HERE/app_main.o"
echo "[build_ada] done (embedded profile): $HERE/app_main.o"
