#!/bin/bash
# Derive board_config.h (for the C bootloader shim) and board_config.env (for the
# shell scripts) from a board.ads.  Each PROJECT now owns its board.ads, so:
#   gen_board_config.sh [BOARD_ADS] [OUTDIR]
#     BOARD_ADS  the project's config/board.ads   (default: the one next to me,
#                i.e. the SDK template/default kept for the host tools)
#     OUTDIR     where to write board_config.{h,env}  (default: dir of BOARD_ADS)
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ADS="${1:-$HERE/board.ads}"
[ -f "$ADS" ] || { echo "gen_board_config: no such board.ads: $ADS" >&2; exit 1; }
OUTDIR="${2:-$(cd "$(dirname "$ADS")" && pwd)}"
mkdir -p "$OUTDIR"

# pull "<Name> : constant := <expr>;" -> evaluate the (simple arithmetic) <expr>
val () {   # $1 = constant name
    local rhs
    rhs="$(sed -n "s/.*$1[[:space:]]*:[[:space:]]*constant[[:space:]]*:=[[:space:]]*\(.*\);.*/\1/p" "$ADS")"
    [ -n "$rhs" ] || { echo "board.ads: $1 not found in $ADS" >&2; exit 1; }
    echo $(( rhs ))
}

FLASH=$(val Flash_Size)
PSRAM=$(val PSRAM_Size)
PAGES=$(( PSRAM / 65536 ))      # 64 KB MMU pages

# human flash-size keyword for esptool's --flash_size (e.g. 2MB / 4MB)
if   (( FLASH % (1024*1024) == 0 )); then FLASH_STR="$(( FLASH / 1024 / 1024 ))MB"
elif (( FLASH % 1024 == 0 ));        then FLASH_STR="$(( FLASH / 1024 ))KB"
else FLASH_STR="${FLASH}B"; fi

cat > "$OUTDIR/board_config.h" <<EOF
/* Generated from board.ads by gen_board_config.sh -- DO NOT EDIT. */
#ifndef BOARD_CONFIG_H
#define BOARD_CONFIG_H
#define BOARD_FLASH_SIZE  ${FLASH}u
#define BOARD_PSRAM_SIZE  ${PSRAM}u
#define BOARD_PSRAM_PAGES ${PAGES}u    /* PSRAM_Size / 64 KB */
#endif
EOF

cat > "$OUTDIR/board_config.env" <<EOF
# Generated from board.ads by gen_board_config.sh -- DO NOT EDIT.
BOARD_FLASH_SIZE=${FLASH}
BOARD_FLASH_SIZE_STR=${FLASH_STR}
BOARD_PSRAM_SIZE=${PSRAM}
BOARD_PSRAM_PAGES=${PAGES}
EOF

echo "[board] flash=${FLASH} psram=${PSRAM} (${PAGES} pages) -> $OUTDIR/board_config.{h,env}"
