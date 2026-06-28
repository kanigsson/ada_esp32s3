#!/bin/bash
# Build the native Modbus.Master harness and run it against the stdlib Python
# Modbus slave (no external deps).  Requires a native GNAT + gprbuild + python3.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
AL="$HOME/.local/share/alire/toolchains"
NATIVE="$(ls -d "$AL"/gnat_native_* 2>/dev/null | sort | tail -1)"
GPR="$(ls -d "$AL"/gprbuild_* 2>/dev/null | sort | tail -1)"
[ -n "$NATIVE" ] && PATH="$NATIVE/bin:$PATH"
[ -n "$GPR" ]    && PATH="$GPR/bin:$PATH"
export PATH
command -v gprbuild >/dev/null || { echo "no native gprbuild found"; exit 1; }
command -v python3  >/dev/null || { echo "no python3 found"; exit 1; }

gprbuild -P modbus_master_host.gpr -q

# Start the slave on an ephemeral port; read the port it prints.
PORT_FILE="$(mktemp)"
python3 modbus_slave.py 0 > "$PORT_FILE" &
SLAVE=$!
trap 'kill $SLAVE 2>/dev/null' EXIT
for _ in $(seq 1 50); do
  PORT="$(awk '/^PORT/{print $2}' "$PORT_FILE")"
  [ -n "$PORT" ] && break
  sleep 0.1
done
[ -n "$PORT" ] || { echo "slave did not start"; exit 1; }

./modbus_master_host "$PORT"
