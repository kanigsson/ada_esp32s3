#!/bin/bash
# Build the IDF-free 2nd-stage bootloader -> bootloader.bin (flash @ 0x0).
# The loader core is ZFP-style Ada (src/boot_main.adb): compiled -gnatp /
# No_Elaboration against the pinned runtime's system.ads into a relocatable
# boot_main.o that needs no binder (adainit) and pulls no runtime at link, so the
# linked output is genuinely runtime-free.  start.S is the asm prologue;
# psram_boot.c is the thin C shim over the vendored octal-PSRAM IDF blobs.
#
# The PSRAM size baked into the binary comes from board_config.h, so each PROJECT
# (its own board.ads) can need its own bootloader.  These env vars let bare_build.sh
# build a project-specific one without touching the SDK copy (all default to the
# in-tree SDK build):
#   BOARD_CFG_DIR  dir holding board_config.h (-I for psram_boot.c).  If it also has
#                  a board.ads (the SDK default/template), it's (re)generated from it.
#   BOOT_OBJ       intermediate objects + boot.elf/.map (default: ./obj)
#   BOOT_OUT       output bootloader.bin (default: ./bootloader.bin)
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
GNAT="$(ls -d "${ESP32S3_ADA_TOOLCHAINS:-$HOME/.local/share/alire/toolchains}"/gnat_xtensa_esp32_elf_*/bin 2>/dev/null | sort -V | tail -1)"
GPR="$(ls -d "${ESP32S3_ADA_TOOLCHAINS:-$HOME/.local/share/alire/toolchains}"/gprbuild_*/bin 2>/dev/null | sort -V | tail -1)"
export PATH="$GPR:$GNAT:$PATH"
# Little-endian ESP32-S3 xtensa config -- REQUIRED for the Ada/C compiles AND the
# final link; without it the toolchain emits/links big-endian (esptool rejects it).
export XTENSA_GNU_CONFIG="$(realpath "$REPO/crates/xtensa-dynconfig/xtensa-dynconfig/xtensa_esp32s3.so")"
export GPR_PROJECT_PATH="$REPO/crates/esp32s3_rts"

GCC=xtensa-esp32-elf-gcc
CFLAGS="-mlongcalls -ffunction-sections -fdata-sections -Os -Wall -Werror -nostdlib"
SDKCFG="$REPO/examples/common/bare/config"
O="${BOOT_OBJ:-$HERE/obj}"; mkdir -p "$O"
BOARD_CFG_DIR="${BOARD_CFG_DIR:-$SDKCFG}"
OUT="${BOOT_OUT:-$HERE/bootloader.bin}"

# board_config.h (PSRAM size) must be in BOARD_CFG_DIR.  If that dir carries a
# board.ads (the SDK default/template), (re)generate from it; otherwise the caller
# (bare_build.sh, per-project) has already put a current board_config.h there.
[ -f "$BOARD_CFG_DIR/board.ads" ] && \
    bash "$SDKCFG/gen_board_config.sh" "$BOARD_CFG_DIR/board.ads" "$BOARD_CFG_DIR" >/dev/null
[ -f "$BOARD_CFG_DIR/board_config.h" ] || { echo "[boot] no board_config.h in $BOARD_CFG_DIR" >&2; exit 1; }

# 1. Loader core in ZFP Ada -> obj/boot_main.o (board-INDEPENDENT, stays in ./obj).
bash "$REPO/crates/esp32s3_rts/gen_runtime.sh" >/dev/null
( cd "$HERE" && gprbuild -c -p -q -P boot.gpr )
BMO="$HERE/obj/boot_main.o"

# 2. asm prologue + PSRAM C shim (board_config.h on its include path) + glue.
$GCC $CFLAGS -c "$HERE/start.S"                          -o "$O/start.o"
$GCC $CFLAGS -I "$BOARD_CFG_DIR" -c "$HERE/psram_boot.c" -o "$O/psram_boot.o"
$GCC $CFLAGS -c "$HERE/psram_glue.c"                     -o "$O/psram_glue.o"
# From-source MSPI clock/pin-drive config (replaces the 4 mspi_timing/gpio blobs;
# the din "tuning" is a proven no-op -- see PSRAM_BRINGUP_RESEARCH.md).
$GCC $CFLAGS -c "$HERE/mspi_timing_src.c"                -o "$O/mspi_timing_src.o"
# From-source octal-PSRAM chip init (MR program + connect probe via ROM
# esp_rom_opiflash_exec_cmd; cache phases from golden state) -- replaces the last
# vendored blob, esp_psram_impl_octal.c.obj.
$GCC $CFLAGS -c "$HERE/psram_impl_src.c"                 -o "$O/psram_impl_src.o"

# All five vendored IDF objects are now retired; the PSRAM bring-up is from-source.
PSRAM_OBJS=""

$GCC -nostdlib -no-pie \
    -T "$HERE/boot.ld" -T "$HERE/rom.ld" \
    -Wl,-e,_start -Wl,-Map="$O/boot.map" \
    -o "$O/boot.elf" \
    "$BMO" "$O/start.o" "$O/psram_boot.o" "$O/psram_glue.o" \
    "$O/mspi_timing_src.o" "$O/psram_impl_src.o" $PSRAM_OBJS

# Package boot.elf -> bootloader.bin with our own Ada esp_elf2image (byte-identical
# to esptool, verified) so the bootloader build needs no esptool either.  Set
# ESP_USE_ESPTOOL=1 to fall back.
if [ -n "${ESP_USE_ESPTOOL:-}" ]; then
    ESPTOOL="esptool.py"; command -v esptool.py >/dev/null || ESPTOOL="python3 -m esptool"
    $ESPTOOL --chip esp32s3 elf2image --flash_mode dio --flash_freq 80m --flash_size 2MB \
        -o "$OUT" "$O/boot.elf"
else
    E2I="$REPO/examples/common/bare/elf2image/esp_elf2image"
    if [ ! -x "$E2I" ]; then
        NATGNAT="$(ls -d "${ESP32S3_ADA_TOOLCHAINS:-$HOME/.local/share/alire/toolchains}"/gnat_native_*/bin 2>/dev/null | sort -V | tail -1)"
        ( cd "$REPO/examples/common/bare/elf2image" && PATH="$NATGNAT:$GPR:$PATH" gprbuild -q -P esp_elf2image.gpr )
    fi
    "$E2I" "$O/boot.elf" "$OUT"
fi

echo "[boot] built (ZFP-Ada loader + C PSRAM shim): $OUT"
