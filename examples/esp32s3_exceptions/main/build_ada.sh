#!/bin/bash
# Build this app's Ada (app.gpr) against the PINNED crate runtime -- selecting the
# EMBEDDED profile (full exception propagation + finalization) -- into a
# relocatable app_main.o that the bootloader's image links.  Light-tasking is
# No_Exception_Propagation, so the propagation/re-raise steps need this profile.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"        # main/
EX="$(cd "$HERE/.." && pwd)"                 # examples/esp32s3_exceptions/
REPO="$(cd "$EX/../.." && pwd)"              # repo root
RTCRATE="$REPO/crates/esp32s3_rts"
DYNDIR="$REPO/crates/xtensa-dynconfig"
DYNCFG="$DYNDIR/xtensa-dynconfig/xtensa_esp32s3.so"

GNAT="$(ls -d "$HOME"/.local/share/alire/toolchains/gnat_xtensa_esp32_elf_*/bin 2>/dev/null | sort -V | tail -1)"
GPR="$(ls -d "$HOME"/.local/share/alire/toolchains/gprbuild_*/bin 2>/dev/null | sort -V | tail -1)"
export PATH="$GPR:$GNAT:$PATH"

[ -f "$DYNCFG" ] || alr -C "$DYNDIR" build
export XTENSA_GNU_CONFIG="$(realpath "$DYNCFG")"
export ESP32S3_RTS_PROFILE=embedded

export GPR_PROJECT_PATH="$RTCRATE${GPR_PROJECT_PATH:+:$GPR_PROJECT_PATH}"
bash "$RTCRATE/gen_runtime.sh"
( cd "$EX" && gprbuild -p -P app.gpr )
cp "$EX/obj/ada_app.o" "$HERE/app_main.o"

# The runtime's System.Memory exports malloc/free etc. for C interop; localise
# them so they don't clash with the bare libc's at link time (Ada's own `new`
# path is self-contained inside app_main.o).
OBJCOPY="$(ls -d "$HOME"/.local/share/alire/toolchains/gnat_xtensa_esp32_elf_*/bin/xtensa-esp32-elf-objcopy 2>/dev/null | sort -V | tail -1)"
for s in malloc calloc free realloc memcpy memset; do LOC="$LOC --localize-symbol=$s"; done
"$OBJCOPY" $LOC "$HERE/app_main.o"
echo "[build_ada] done (embedded profile): $HERE/app_main.o"
