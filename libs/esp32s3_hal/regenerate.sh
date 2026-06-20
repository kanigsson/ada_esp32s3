#!/bin/bash
# Regenerate the ESP32-S3 register layer in svd/ from a CMSIS-SVD file using
# svd2ada (AdaCore), built from the LATEST source.  Run this MANUALLY after
# changing the SVD or the svd2ada options -- it is NOT part of the build; the
# generated output is committed so consumers never need svd2ada.
#
# SVD source: the official espressif/svd repo, pinned to a commit (currently
# ESP32-S3 SVD version 21).  This supersedes the older Arduino-bundled SVD (v12),
# whose only base-address defect (INTERRUPT_CORE1 = 0x600C2800) is fixed upstream
# here (0x600C2000) -- so no base patch is needed.  Override with a local file
# via ESP32S3_SVD=/path.svd.
#
# NOTE: the Alire-indexed svd2ada is too old -- it leaves %s template
# placeholders in dimensioned register arrays (e.g. RMT), which do not compile;
# so we build the current source instead.  Two post-processes follow: qualify
# System->Standard.System in the SYSTEM peripheral (case-insensitive name clash),
# and re-expand the flattened Apache header.
#
#   ./regenerate.sh            # fetches the pinned espressif/svd esp32s3.svd
#   ESP32S3_SVD=/path.svd ./regenerate.sh
#
# Root package is ESP32S3_Registers (NOT Interfaces.ESP32S3: GNAT forbids
# user-defined descendants of Interfaces outside the runtime).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$HERE/.svd2ada"
mkdir -p "$WORK"

# Pinned espressif/svd commit (esp32s3.svd v21); cached in .svd2ada/.
SVD_COMMIT="104da3c8e28a3c3a088c68a5ad1d31272b3d43ef"
SVD="${ESP32S3_SVD:-}"
if [ -z "$SVD" ]; then
    SVD="$WORK/esp32s3.svd"          # clean name -> clean "generated from" comment
    MARK="$WORK/.svd-commit"
    if [ "$(cat "$MARK" 2>/dev/null)" != "$SVD_COMMIT" ]; then
        echo "[regen] fetching espressif/svd esp32s3.svd @ ${SVD_COMMIT:0:10} ..."
        curl -fsSL "https://raw.githubusercontent.com/espressif/svd/$SVD_COMMIT/svd/esp32s3.svd" -o "$SVD"
        echo "$SVD_COMMIT" > "$MARK"
    fi
fi
[ -f "$SVD" ] || { echo "SVD not found: $SVD  (set ESP32S3_SVD=/path/to/esp32s3.svd)"; exit 1; }

# Build svd2ada from the latest AdaCore source (Alire resolves its xmlada dep).
# Cloned + built into .svd2ada/; cached after the first run.
SVD2ADA="$WORK/svd2ada-src/bin/svd2ada"
if [ ! -x "$SVD2ADA" ]; then
    echo "[regen] cloning + building svd2ada from source (one-time; needs network) ..."
    rm -rf "$WORK/svd2ada-src"; mkdir -p "$WORK"
    git clone --depth 1 https://github.com/AdaCore/svd2ada.git "$WORK/svd2ada-src"
    ( cd "$WORK/svd2ada-src" && alr -n build )
fi

echo "[regen] svd2ada: $SVD2ADA"
rm -rf "$HERE/svd"; mkdir -p "$HERE/svd"
"$SVD2ADA" "$SVD" -o "$HERE/svd" -p ESP32S3_Registers --boolean
echo "[regen] regenerated svd/ ($(ls "$HERE"/svd/*.ads | wc -l) packages) from $SVD"

# The SVD peripheral named "SYSTEM" generates package ESP32S3_Registers.SYSTEM;
# Ada is case-insensitive, so a bare `System.X` inside it resolves to that child
# (which has no such X) instead of Standard.System.  Qualify it so SYSTEM compiles.
sed -i -E "s/\\bSystem\\./Standard.System./g; s/\\bSystem'/Standard.System'/g" \
    "$HERE/svd/esp32s3_registers-system.ads"
echo "[regen] qualified System -> Standard.System in the SYSTEM peripheral"

# (The INTERRUPT_CORE1 base is correct in the v21 SVD -- 0x600C2000, shared with
# INTERRUPT_CORE0 -- so the base patch the old Arduino v12 SVD needed is gone.)

# svd2ada flattens the SVD's Apache-2.0 header onto a single line.  Apache-2.0
# requires the notice be retained; re-expand it to a readable comment block (the
# license obligation is unchanged either way -- this is purely cosmetic).
python3 - "$HERE/svd" <<'PY'
import glob, sys, re
def tidy(year):
    return f"""--  Copyright {year} Espressif Systems (Shanghai) PTE LTD
--
--  Licensed under the Apache License, Version 2.0 (the "License");
--  you may not use this file except in compliance with the License.
--  You may obtain a copy of the License at
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software
--  distributed under the License is distributed on an "AS IS" BASIS,
--  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--  See the License for the specific language governing permissions and
--  limitations under the License."""
# Match the flattened one-line header for any copyright year.
flat = re.compile(r"^--  Copyright (\d{4}) Espressif Systems .*limitations under the License\.$")
n = 0
for f in glob.glob(sys.argv[1] + "/*.ads"):
    lines = open(f, encoding="utf-8").read().split("\n")
    out = []
    for l in lines:
        m = flat.match(l)
        out.append(tidy(m.group(1)) if m else l)
    if out != lines:
        open(f, "w", encoding="utf-8").write("\n".join(out)); n += 1
print(f"[regen] tidied the Apache header in {n} file(s)")
PY
