# Set up the ESP32-S3 Ada SDK environment.  SOURCE this file (do not execute):
#
#     . /path/to/this/repo/export.sh
#     source /path/to/this/repo/export.sh
#
# It exports ESP32S3_ADA_SDK (the SDK root), puts the `esp32-ada` launcher on
# PATH, and adds the runtime project to GPR_PROJECT_PATH so a standalone project
# anywhere on disk can `with "esp32s3_rts.gpr"` (both gprbuild AND the Ada
# Language Server resolve it -- launch your editor from a shell that sourced this).
# Add the line to ~/.bashrc to make it permanent.

# Resolve this script's dir whether sourced from bash or zsh.
if [ -n "${BASH_SOURCE:-}" ]; then __esp_ada_self="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ];  then __esp_ada_self="${(%):-%N}"
else __esp_ada_self="$0"; fi

ESP32S3_ADA_SDK="$(cd "$(dirname "$__esp_ada_self")" && pwd)"
export ESP32S3_ADA_SDK
unset __esp_ada_self

# esp32-ada launcher on PATH (idempotent).
case ":$PATH:" in
  *":$ESP32S3_ADA_SDK/tools/bin:"*) ;;
  *) PATH="$ESP32S3_ADA_SDK/tools/bin:$PATH"; export PATH ;;
esac

# Runtime project + every reusable library (libs/*/) on GPR_PROJECT_PATH, so
# `with "esp32s3_rts.gpr"` / `with "esp32s3_hal.gpr"` resolve with no relative path
# -- for gprbuild AND ada_language_server (IntelliSense).  Auto-discovered: adding a
# library = drop libs/<name>/<name>.gpr; no edit here.
for __gpp in "$ESP32S3_ADA_SDK/crates/esp32s3_rts" "$ESP32S3_ADA_SDK"/libs/*/; do
  __gpp="${__gpp%/}"; [ -d "$__gpp" ] || continue
  case ":${GPR_PROJECT_PATH:-}:" in
    *":$__gpp:"*) ;;
    *) GPR_PROJECT_PATH="$__gpp${GPR_PROJECT_PATH:+:$GPR_PROJECT_PATH}"; export GPR_PROJECT_PATH ;;
  esac
done
unset __gpp

echo "ESP32-S3 Ada SDK: $ESP32S3_ADA_SDK"
echo "  'esp32-ada' is on PATH.  New project:  mkdir myapp && cd myapp && esp32-ada init"
