#!/usr/bin/env bash
# Run SPARK proof against the REAL xtensa-esp32-elf target.
#
# gnatprove works fine cross-targeted: target word sizes / endianness / alignment
# come from a generated target.atp (-gnateT), NOT from `for Target` (which only
# selects the runtime library).  target.atp MUST be generated with the
# xtensa-dynconfig plugin ACTIVE, or the compiler reports a generic big-endian
# Xtensa and the params are wrong -- this script handles that.
#
# Steps:
#   1. Resolve the toolchain (xtensa GNAT + gprbuild) Alire-free via tools/sdk-env.sh,
#      and build the xtensa-dynconfig plugin if missing.
#   2. Generate proof/target.atp with that plugin active (assert little-endian).
#   3. Generate the bare-board runtime if missing, then run gnatprove.
#
# gnatprove is found on PATH, via $GNATPROVE_BIN, or auto-located in the Alire
# releases dir.  Usage:
#   ./proof/prove.sh                                  # default: sparknacl_proof.gpr
#   ./proof/prove.sh -P proof/x509_proof.gpr --level=2 -f
#   ESP32S3_RTS_PROFILE=embedded ./proof/prove.sh ...
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"      # proof/
repo="$(cd "$here/.." && pwd)"             # repo root
: "${ESP32S3_RTS_PROFILE:=embedded}"
export ESP32S3_RTS_PROFILE

rtcrate="$repo/crates/esp32s3_rts"
dyndir="$repo/crates/xtensa-dynconfig"
dyncfg="$dyndir/xtensa-dynconfig/xtensa_esp32s3.so"
runtime="$rtcrate/${ESP32S3_RTS_PROFILE}-esp32s3"

# 1. Toolchain + dynconfig, Alire-free.
# shellcheck source=../tools/sdk-env.sh
. "$repo/tools/sdk-env.sh"
esp32s3_toolchain_on_path
esp32s3_build_dynconfig "$dyndir" "$dyncfg"
export XTENSA_GNU_CONFIG="$(realpath "$dyncfg")"
export GPR_PROJECT_PATH="$rtcrate${GPR_PROJECT_PATH:+:$GPR_PROJECT_PATH}"

# Locate gnatprove (not part of the cross toolchain).
if [ -n "${GNATPROVE_BIN:-}" ]; then PATH="$GNATPROVE_BIN:$PATH"; fi
if ! command -v gnatprove >/dev/null; then
   gp="$(ls -d "$HOME"/.local/share/alire/releases/gnatprove_*/bin 2>/dev/null | sort -V | tail -1 || true)"
   [ -n "$gp" ] && PATH="$gp:$PATH"
fi
export PATH
command -v gnatprove >/dev/null || {
   echo "error: gnatprove not found (set GNATPROVE_BIN or install the Alire gnatprove crate)."; exit 1; }

# 2. Faithful target parameters (dynconfig is now active in the env).
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf 'package Dummy is\nend Dummy;\n' > "$tmp/dummy.ads"
( cd "$tmp" && xtensa-esp32-elf-gcc -c -gnatet=target.atp --RTS="$runtime" dummy.ads )
cp "$tmp/target.atp" "$here/target.atp"
grep -q '^Bytes_BE *0' "$here/target.atp" && grep -q '^Words_BE *0' "$here/target.atp" \
   || { echo "error: target.atp looks big-endian -- dynconfig plugin not active?"; exit 1; }

# 3. Generate the runtime if missing, then prove.
[ -d "$runtime" ] || bash "$rtcrate/gen_runtime.sh"

# Default project if the caller didn't pass -P.
proj="proof/sparknacl_proof.gpr"
for a in "$@"; do case "$a" in -P*|--project=*) proj="" ;; esac; done
exec gnatprove ${proj:+-P "$proj"} --report=all "$@"
