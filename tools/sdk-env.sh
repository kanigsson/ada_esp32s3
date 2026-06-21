# Alire-free toolchain + dynconfig helpers for the ESP32-S3 Ada SDK.
# SOURCE this file (do not execute).
#
# Resolves the xtensa cross GNAT, gprbuild and native GNAT from a configurable
# search root and puts them on PATH, and builds the xtensa-dynconfig core-config
# plugin -- all WITHOUT Alire.  `alr` is never invoked.
#
#   ESP32S3_ADA_TOOLCHAINS   search root holding the gnat_*/gprbuild_* dirs.
#                            Default: Alire's install dir (existing dev boxes).
#                            A self-contained bundle sets this to its own
#                            toolchains/, or ships $ESP32S3_ADA_SDK/toolchains/.
#
# Note: the very first dynconfig build still clones its upstream source over the
# network; vendor it for a fully offline bundle (Phase 2).

: "${ESP32S3_ADA_TOOLCHAINS:=$HOME/.local/share/alire/toolchains}"
if [ -n "${ESP32S3_ADA_SDK:-}" ] && [ -d "$ESP32S3_ADA_SDK/toolchains" ]; then
    ESP32S3_ADA_TOOLCHAINS="$ESP32S3_ADA_SDK/toolchains"   # bundled toolchain wins
fi
export ESP32S3_ADA_TOOLCHAINS

# Newest bin/ under the search root matching glob $1 (or empty if none).
esp32s3_tc_bin () { ls -d "$ESP32S3_ADA_TOOLCHAINS"/$1/bin 2>/dev/null | sort -V | tail -1; }

# Put gprbuild + the xtensa cross GNAT + native GNAT on PATH (idempotent), and
# export ESP32S3_GPRBUILD_BIN / ESP32S3_GNAT_NATIVE_BIN for callers that need an
# explicit native-first PATH (the native host tools).
esp32s3_toolchain_on_path () {
    ESP32S3_GPRBUILD_BIN="$(esp32s3_tc_bin 'gprbuild_*')"
    ESP32S3_GNAT_XTENSA_BIN="$(esp32s3_tc_bin 'gnat_xtensa_esp32_elf_*')"
    ESP32S3_GNAT_NATIVE_BIN="$(esp32s3_tc_bin 'gnat_native_*')"
    export ESP32S3_GPRBUILD_BIN ESP32S3_GNAT_XTENSA_BIN ESP32S3_GNAT_NATIVE_BIN
    local d
    for d in "$ESP32S3_GPRBUILD_BIN" "$ESP32S3_GNAT_XTENSA_BIN" "$ESP32S3_GNAT_NATIVE_BIN"; do
        [ -n "$d" ] || continue
        case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH" ;; esac
    done
    export PATH
}

# Build the xtensa-dynconfig plugin (the XTENSA_GNU_CONFIG .so) without Alire,
# if the output is missing.  This runs exactly what `alr build` ran for the
# crate: its pre-build actions (scripts/setup.sh + `make -C xtensa-dynconfig`).
#   $1 = crate dir (.../crates/xtensa-dynconfig)   $2 = expected .so path
esp32s3_build_dynconfig () {
    local dyndir="$1" dyncfg="$2"
    [ -f "$dyncfg" ] && return 0
    echo "[sdk] building xtensa-dynconfig plugin (one-time, Alire-free)"
    ( cd "$dyndir" && bash ./scripts/setup.sh && make -C xtensa-dynconfig CC=gcc )
}
