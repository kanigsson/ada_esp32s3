#!/usr/bin/env bash
#
#  get-openocd.sh -- fetch the pinned Espressif openocd-esp32 for THIS host into a
#  git-ignored tools/openocd/.  Debugging is the only part of this project that
#  needs OpenOCD (build/flash/run do not), and OpenOCD is a large, GPL, per-platform
#  native binary -- so we pin-and-download it (like the Alire toolchains) instead of
#  committing it to git.  GDB is NOT fetched: it ships with the Alire gnat_xtensa
#  crate (xtensa-esp32-elf-gdb).
#
#  Pinned from Espressif's tools.json; URLs + SHA-256 are baked in below so the
#  download is verified and reproducible with no ESP-IDF present.
#
#    ./tools/get-openocd.sh            # fetch if missing
#    ./tools/get-openocd.sh --force    # re-fetch even if present
#
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HERE/openocd"                       # git-ignored
VERSION="0.12.0-esp32-20260304"
BASE="https://github.com/espressif/openocd-esp32/releases/download/v${VERSION}"
STAMP="$DEST/.version"

die () { echo "get-openocd: $*" >&2; exit 1; }

# host -> Espressif asset key
os="$(uname -s)"; arch="$(uname -m)"
case "$os" in
  Linux)  case "$arch" in
            x86_64)        key=linux-amd64 ;;
            aarch64|arm64) key=linux-arm64 ;;
            armv7l)        key=linux-armhf ;;
            *) die "unsupported Linux arch '$arch'" ;;
          esac ;;
  Darwin) case "$arch" in
            arm64)  key=macos-arm64 ;;
            x86_64) key=macos ;;
            *) die "unsupported macOS arch '$arch'" ;;
          esac ;;
  *) die "unsupported OS '$os' (Windows: download $BASE/openocd-esp32-win64-${VERSION}.zip by hand into tools/openocd/)" ;;
esac

# pinned SHA-256 per asset key (from tools.json, v${VERSION})
sha_for () {
  case "$1" in
    linux-amd64)  echo dbd7ecf751431c70628176fbf1ce404c3ff28027e91b66bda7f834a2d5ff5b81 ;;
    linux-arm64)  echo 7fbe82e36f8e34a7a3118045fd7888754afbfe4c60cfaee0ac70663fd5965f63 ;;
    linux-armhf)  echo 847df6f58308fddbb00d0db71ad971d9ab6346d091bb060bd98c053a0d4e4322 ;;
    macos)        echo be6951d9766f88fad11060314f6c3469c56715a60f2715aaeb7d806afc935c0d ;;
    macos-arm64)  echo a36099d3a47241e816693d9bd719198e4667ad67f0a027404d90584d44b6842d ;;
    *) die "no pinned sha for '$1'" ;;
  esac
}

ASSET="openocd-esp32-${key}-${VERSION}.tar.gz"
URL="$BASE/$ASSET"
WANT="$(sha_for "$key")"

if [ "${1:-}" != "--force" ] && [ -x "$DEST/openocd-esp32/bin/openocd" ] \
   && [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$VERSION" ]; then
  echo "get-openocd: already have v$VERSION at $DEST/openocd-esp32"; exit 0
fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "get-openocd: downloading $ASSET ..."
if command -v curl >/dev/null; then curl -fL -o "$tmp/$ASSET" "$URL"
elif command -v wget >/dev/null; then wget -O "$tmp/$ASSET" "$URL"
else die "need curl or wget"; fi

echo "get-openocd: verifying SHA-256 ..."
if command -v sha256sum >/dev/null; then got="$(sha256sum "$tmp/$ASSET" | cut -d' ' -f1)"
else got="$(shasum -a 256 "$tmp/$ASSET" | cut -d' ' -f1)"; fi
[ "$got" = "$WANT" ] || die "checksum mismatch for $ASSET (got $got, want $WANT)"

rm -rf "$DEST"; mkdir -p "$DEST"
tar -xzf "$tmp/$ASSET" -C "$DEST"          # unpacks to $DEST/openocd-esp32/
echo "$VERSION" > "$STAMP"
echo "get-openocd: installed v$VERSION -> $DEST/openocd-esp32/bin/openocd"
