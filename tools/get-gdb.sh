#!/usr/bin/env bash
#
#  get-gdb.sh -- fetch the pinned Espressif Xtensa GDB (provides
#  xtensa-esp32s3-elf-gdb) for THIS host into a git-ignored tools/gdb/.
#
#  WHY a separate GDB and not the Alire crate's xtensa-esp32-elf-gdb: that one is
#  built for the ESP32 (LX6) register set and FAILS on the ESP32-S3 (LX7) with
#  "'g' packet reply too long (452 vs 608)" -- Xtensa GDB uses its compiled-in
#  register layout, which differs by core.  The S3 needs the s3-specific GDB.
#  (Verified on hardware 2026-06-14.)
#
#  Pinned from Espressif's tools.json; URL + SHA-256 baked in, verified download.
#
#    ./tools/get-gdb.sh            # fetch if missing
#    ./tools/get-gdb.sh --force    # re-fetch even if present
#
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HERE/gdb"                           # git-ignored
VERSION="16.3_20250913"
BASE="https://github.com/espressif/binutils-gdb/releases/download/esp-gdb-v${VERSION}"
STAMP="$DEST/.version"

die () { echo "get-gdb: $*" >&2; exit 1; }

os="$(uname -s)"; arch="$(uname -m)"
case "$os" in
  Linux)  case "$arch" in
            x86_64)        key=x86_64-linux-gnu ;;
            aarch64|arm64) key=aarch64-linux-gnu ;;
            *) die "unsupported Linux arch '$arch'" ;;
          esac ;;
  Darwin) case "$arch" in
            arm64)  key=aarch64-apple-darwin24.5 ;;
            x86_64) key=x86_64-apple-darwin24.5 ;;
            *) die "unsupported macOS arch '$arch'" ;;
          esac ;;
  *) die "unsupported OS '$os'" ;;
esac

sha_for () {
  case "$1" in
    x86_64-linux-gnu)         echo 16d05c9104ff84529ac3799abb04d5666c193131ab461f153040721728b48730 ;;
    aarch64-linux-gnu)        echo ecbd53ba28cf24301be8260249bfcfb60567f938f4402797617c8a0fc170dc7d ;;
    x86_64-apple-darwin24.5)  echo 8341493abc87e6ae468f4eda16c768b2ddb20c98336e1c491a3801ad823680ae ;;
    aarch64-apple-darwin24.5) echo 251e3be9c9436d9ab7fee6c05519fd816a05e63bd47495e24ea4e354881a851c ;;
    *) die "no pinned sha for '$1'" ;;
  esac
}

ASSET="xtensa-esp-elf-gdb-${VERSION}-${key}.tar.gz"
URL="$BASE/$ASSET"
WANT="$(sha_for "$key")"

if [ "${1:-}" != "--force" ] && [ -x "$DEST/xtensa-esp-elf-gdb/bin/xtensa-esp32s3-elf-gdb" ] \
   && [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$VERSION" ]; then
  echo "get-gdb: already have v$VERSION at $DEST/xtensa-esp-elf-gdb"; exit 0
fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "get-gdb: downloading $ASSET (~36 MB) ..."
if command -v curl >/dev/null; then curl -fL -o "$tmp/$ASSET" "$URL"
elif command -v wget >/dev/null; then wget -O "$tmp/$ASSET" "$URL"
else die "need curl or wget"; fi

echo "get-gdb: verifying SHA-256 ..."
if command -v sha256sum >/dev/null; then got="$(sha256sum "$tmp/$ASSET" | cut -d' ' -f1)"
else got="$(shasum -a 256 "$tmp/$ASSET" | cut -d' ' -f1)"; fi
[ "$got" = "$WANT" ] || die "checksum mismatch for $ASSET (got $got, want $WANT)"

rm -rf "$DEST"; mkdir -p "$DEST"
tar -xzf "$tmp/$ASSET" -C "$DEST"          # unpacks to $DEST/xtensa-esp-elf-gdb/
echo "$VERSION" > "$STAMP"
echo "get-gdb: installed v$VERSION -> $DEST/xtensa-esp-elf-gdb/bin/xtensa-esp32s3-elf-gdb"
