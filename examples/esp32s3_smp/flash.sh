#!/bin/bash
# Flash via vendored bootloader + partition table + app.bin (esptool).  $1 = port.
HERE="$(cd "$(dirname "$0")" && pwd)"
exec bash "$HERE/../common/bare/bare_flash.sh" "$HERE" "$1"
