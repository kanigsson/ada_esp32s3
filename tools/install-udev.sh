#!/usr/bin/env bash
#
#  install-udev.sh -- grant this user access to the ESP32-S3 USB device so that
#  flashing (/dev/ttyACM*) and on-chip debug (USB-JTAG via OpenOCD) work without
#  root.  Installs tools/60-esp32-ada.rules into /etc/udev/rules.d, reloads udev,
#  and adds the user to the plugdev + dialout groups (the non-logind fallback).
#
#  This is the one step an AppImage cannot do for you: a udev rule must live on
#  the host and only root can write it.  Run it once per machine:
#
#      ./x setup-device                 # (re-runs itself with sudo)
#      sudo bash tools/install-udev.sh  # equivalent
#
#  Options:
#      --uninstall    remove the rule (group membership is left alone)
#      --user NAME    add NAME to the groups (default: $SUDO_USER / the caller)
#      --no-reload    skip 'udevadm' reload/trigger (for packaging/test)
#  Honors $DESTDIR for staged installs (testing).
#
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULE_SRC="$HERE/60-esp32-ada.rules"
RULE_NAME="60-esp32-ada.rules"
DESTDIR="${DESTDIR:-}"
RULE_DST="$DESTDIR/etc/udev/rules.d/$RULE_NAME"

say () { echo "setup-device: $*"; }
die () { echo "setup-device: $*" >&2; exit 1; }

action="install"; reload=1
# Who should the group memberships apply to?  When run via sudo/pkexec the real
# user is in SUDO_USER / PKEXEC_UID, not $USER (which is root).
target_user="${SUDO_USER:-}"
[ -z "$target_user" ] && [ -n "${PKEXEC_UID:-}" ] && target_user="$(getent passwd "$PKEXEC_UID" | cut -d: -f1)"
[ -z "$target_user" ] && target_user="${USER:-}"

while [ $# -gt 0 ]; do
    case "$1" in
        --uninstall) action="uninstall"; shift ;;
        --user)      target_user="$2"; shift 2 ;;
        --no-reload) reload=0; shift ;;
        -h|--help)   sed -n '2,22p' "$0" | sed 's/^#  \{0,1\}//; s/^#//'; exit 0 ;;
        *)           die "unknown option '$1' (try --help)" ;;
    esac
done

# Re-exec with root unless we're only staging into a DESTDIR.
if [ "$(id -u)" != 0 ] && [ -z "$DESTDIR" ]; then
    say "needs root to write $RULE_DST -- escalating ..."
    if command -v sudo >/dev/null; then exec sudo -E "$0" "$@"
    elif command -v pkexec >/dev/null; then exec pkexec "$0" "$@"
    else die "run me as root (no sudo/pkexec found): sudo bash $0"; fi
fi

if [ "$action" = uninstall ]; then
    if [ -f "$RULE_DST" ]; then rm -f "$RULE_DST"; say "removed $RULE_DST"
    else say "nothing to remove ($RULE_DST not present)"; fi
else
    [ -f "$RULE_SRC" ] || die "rule source missing: $RULE_SRC"
    mkdir -p "$(dirname "$RULE_DST")"
    install -m 0644 "$RULE_SRC" "$RULE_DST"
    say "installed $RULE_DST"

    # Group fallback (for systems without logind/uaccess).  Create plugdev if the
    # distro doesn't ship it; dialout always exists.  Skipped for staged installs.
    if [ -z "$DESTDIR" ] && [ -n "$target_user" ] && [ "$target_user" != root ]; then
        getent group plugdev >/dev/null || { groupadd -r plugdev 2>/dev/null || true; }
        for g in plugdev dialout; do
            getent group "$g" >/dev/null || continue
            if id -nG "$target_user" 2>/dev/null | tr ' ' '\n' | grep -qx "$g"; then
                say "$target_user already in $g"
            else
                usermod -aG "$g" "$target_user" && say "added $target_user to $g"
            fi
        done
    fi
fi

if [ "$reload" = 1 ] && [ -z "$DESTDIR" ] && command -v udevadm >/dev/null; then
    udevadm control --reload-rules && udevadm trigger || say "(udevadm reload/trigger failed -- replug the board)"
    say "udev rules reloaded"
fi

say "done."
if [ "$action" = install ]; then
    echo
    say "NEXT: unplug and replug the board so the new rule applies."
    say "If access still fails on a non-systemd system, log out and back in once"
    say "(so the plugdev/dialout group membership takes effect)."
fi
