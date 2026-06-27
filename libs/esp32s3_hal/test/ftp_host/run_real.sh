#!/bin/bash
# Real-world smoke test: drive FTP_Client (the SAME source the board runs) against
# an actual public FTP server over the internet, via native GNAT.Sockets.
# Usage: ./run_real.sh [host] [path]   (default: ftp.gnu.org /README)
# Needs network access; this is NOT a CI test (run.sh is the offline one).
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

gprbuild -P ftp_host.gpr -q

HOST="${1:-ftp.gnu.org}"
WANT="${2:-/README}"
IP="$(python3 -c "import socket,sys; print(socket.getaddrinfo(sys.argv[1],21,socket.AF_INET)[0][4][0])" "$HOST")"
echo "$HOST = $IP"
./ftp_real "$IP" 21 "$WANT"
