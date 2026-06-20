#!/usr/bin/env bash
#
#  openocd.sh -- launch OpenOCD for the ESP32-S3 built-in USB-JTAG, preferring the
#  pinned copy fetched by get-openocd.sh (tools/openocd/) and falling back to an
#  openocd already on PATH.  Extra args are passed through.
#
#    ./tools/openocd.sh                     # board/esp32s3-builtin.cfg
#    ./tools/openocd.sh -c "init; reset"    # + extra commands
#
#  Adapter-serial pinning: with more than one board the built-in adapter otherwise
#  grabs the FIRST 303a device -- not necessarily the one you flashed -- so debug
#  attaches to the wrong board.  The USB-JTAG serial == the ACM device serial; this
#  picks it up so OpenOCD targets the SAME board, in priority order:
#    1. $ESP_JTAG_SERIAL          (explicit override)
#    2. serial of $ESPPORT        (the serial port being used)
#    3. tools/.jtag_serial        (recorded by the last `./x flash`)
#  None set (single board) -> no pin, OpenOCD's default.
#
#  ESP_ONLYCPU=1 -> debug core 0 only (see the _ONLYCPU note below). Required for a
#  reliable boot-to-app_main breakpoint under VS Code's async debugger.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LOCAL="$HERE/openocd/openocd-esp32"

serial_from_port () {  # $1 = /dev/ttyACMx -> echo the USB-JTAG adapter serial
  local link tgt
  tgt="$(readlink -f "$1" 2>/dev/null)" || return 0
  for link in /dev/serial/by-id/usb-Espressif_USB_JTAG_serial_debug_unit_*; do
    [ -e "$link" ] || continue
    if [ "$(readlink -f "$link")" = "$tgt" ]; then
      basename "$link" | sed -E 's/.*debug_unit_(.+)-if[0-9]+$/\1/'; return 0
    fi
  done
  command -v udevadm >/dev/null 2>&1 && \
    udevadm info -q property -n "$1" 2>/dev/null | sed -n 's/^ID_SERIAL_SHORT=//p' | head -1
}

PIN=""
if   [ -n "${ESP_JTAG_SERIAL:-}" ];                   then PIN="$ESP_JTAG_SERIAL"
elif [ -n "${ESPPORT:-}" ] && [ -e "${ESPPORT:-}" ]; then PIN="$(serial_from_port "$ESPPORT")"
elif [ -s "$HERE/.jtag_serial" ];                    then PIN="$(cat "$HERE/.jtag_serial")"
fi
PIN_ARGS=()
if [ -n "$PIN" ]; then
  PIN_ARGS=(-c "adapter serial $PIN")
  echo "openocd.sh: pinning USB-JTAG adapter serial $PIN" >&2
fi

# Single-core (core 0 only): with ESP_ONLYCPU=1 we tell OpenOCD to manage only
# cpu0 (set _ONLYCPU 0x1 -> _ESP_SMP_TARGET 0). Why this matters for the bare boot:
# core 1 is GATED in hardware until app_main (on core 0) starts it. If OpenOCD owns
# both cores, a `continue` resumes BOTH -- and under GDB/MI *async* mode (what VS
# Code's Native Debug uses) core 1 free-runs into ROM and hits an illegal
# instruction at 0x400003C0, which halts the SMP pair BEFORE core 0 reaches
# app_main (your breakpoint never hits). Debugging only core 0 sidesteps this; the
# app still runs fully on both cores (app_main starts core 1 over hardware regs,
# independent of JTAG) -- you just can't set JTAG breakpoints in core-1 code.
ONLYCPU_ARGS=()
if [ "${ESP_ONLYCPU:-}" = "1" ]; then
  ONLYCPU_ARGS=(-c "set _ONLYCPU 0x1")
  echo "openocd.sh: single-core debug (core 0 only)" >&2
fi

# OpenOCD thread model (set BEFORE the board cfg):
#   ESP_RTOS=none      (DEFAULT) -- no thread awareness; gdb sees the one running
#                       core.  Right for normal app debugging (this runtime never
#                       runs FreeRTOS, so don't let OpenOCD parse FreeRTOS lists).
#   ESP_RTOS=hwthread  -- present EACH of the two LX7 cores as a gdb thread, so
#                       `info threads` shows cpu0 AND cpu1 and you can `bt` each
#                       independently.  ESSENTIAL for SMP / dual-core post-mortem
#                       (e.g. a tasking hang where one core crashed and the other
#                       idles -- the builtin USB-JTAG reaches both cores; the only
#                       trick is asking for both threads).  `./x debug --smp`.
RTOS="${ESP_RTOS:-none}"
[ "$RTOS" = "hwthread" ] && echo "openocd.sh: dual-core (hwthread) -- both cores appear as gdb threads" >&2
if [ -x "$LOCAL/bin/openocd" ]; then
  exec "$LOCAL/bin/openocd" -s "$LOCAL/share/openocd/scripts" \
       -c "set ESP_RTOS $RTOS" "${ONLYCPU_ARGS[@]}" "${PIN_ARGS[@]}" -f board/esp32s3-builtin.cfg "$@"
elif command -v openocd >/dev/null; then
  exec openocd -c "set ESP_RTOS $RTOS" "${ONLYCPU_ARGS[@]}" "${PIN_ARGS[@]}" -f board/esp32s3-builtin.cfg "$@"
else
  echo "openocd.sh: no OpenOCD found." >&2
  echo "            run  ./tools/get-openocd.sh  (or ./x get-openocd) to fetch it." >&2
  exit 1
fi
