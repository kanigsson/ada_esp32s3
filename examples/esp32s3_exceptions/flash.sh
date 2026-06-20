#!/bin/bash
# Flash the exception demo (bootloader + partition table + app.bin).
#   $1 = serial port (default /dev/ttyACM0)
HERE="$(cd "$(dirname "$0")" && pwd)"
exec bash "$HERE/../common/bare/bare_flash.sh" "$HERE" "$1"
