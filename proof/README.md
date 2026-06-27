# SPARK proof scenario

This directory holds the **proof harness** for the SPARKifiable parts of
`ada_esp32s3`. gnatprove proves against the **real `xtensa-esp32-elf` target**:
target word sizes, endianness and alignment come from a generated `target.atp`
fed via `-gnateT` (not from `for Target`, which only selects the runtime
library). This is faithful to the actual silicon — important for the Tier-B
register drivers, where `Object_Size` and the bit layout of the
`Volatile_Full_Access` records are exactly what must be checked.

`target.atp` must be generated with the **xtensa-dynconfig plugin active**
(`XTENSA_GNU_CONFIG` set), otherwise the compiler reports a generic *big-endian*
Xtensa and the parameters are wrong. `proof/prove.sh` handles this; it mirrors
the working setup in the sibling `../lilyt5/prove`. The proof-only projects use
`for Runtime` to pull the bare-board runtime *lazily* and deliberately do **not**
`with` the runtime's `build_libgnat`/`build_libgnarl` projects (that makes
`gnat2why` try to analyse the whole runtime and crash).

## Toolchain

| Tool | Version |
|------|---------|
| `gnatprove` | FSF 15.0 (Alire release `gnatprove_15.1.0`) |
| Provers | Alt-Ergo 2.6.0, cvc5 1.2.1, Z3 |
| Why3 | 1.7.1 |
| `gnat` (xtensa-esp32-elf cross) | 15.2.0 |
| `gprbuild` | 26.0.0 |

The cross GNAT, gprbuild and the xtensa-dynconfig plugin are resolved
Alire-free by `tools/sdk-env.sh` (search root `$ESP32S3_ADA_TOOLCHAINS`,
default `~/.local/share/alire/toolchains`). `gnatprove` is auto-located in
`~/.local/share/alire/releases/gnatprove_*` or taken from `$GNATPROVE_BIN`.
You don't set any of this by hand — `prove.sh` does it.

## Projects

| Project | Covers | Status |
|---------|--------|--------|
| `sparknacl_proof.gpr` | vendored SPARKNaCl crypto primitives | **replays (cross)** — see below |
| `x509_proof.gpr` | `X509.DER` + `X509` spec (phase 1); `Cert_Verify`, `Chain_Verify` later | **phase 1 proved** — see `tier-a-results.md` |

## Running

Always go through `prove.sh` — it sets the toolchain + dynconfig env and
regenerates `target.atp` (asserting little-endian) before invoking gnatprove.
Extra args are forwarded to gnatprove.

```sh
# Default project (sparknacl), full proof, all cores, fail-only report:
./proof/prove.sh --level=1 -j0 --report=fail

# A specific project / unit / level:
./proof/prove.sh -P proof/x509_proof.gpr --level=2 -j0 -u x509-der.adb

# Flow analysis only (fast):
./proof/prove.sh --mode=flow --report=fail

# Profile selection (default embedded):
ESP32S3_RTS_PROFILE=embedded ./proof/prove.sh --level=2
```

## SPARKNaCl replay result (warm-up, steps 1–2)

Proving `sparknacl.adb` (the GF(2²⁵⁵-19) arithmetic core) **cross-targeted to
xtensa-esp32-elf** at `--level=1` (`./proof/prove.sh --level=1 -j0 -u
sparknacl.adb`):

```
SPARK Analysis results        Total   Flow   Provers   Justified   Unproved
Data Dependencies                17     17         .           .          .
Initialization                   68     53        15           .          .
Run-time Checks                 297      .       297           .          .
Assertions                       82      .        82           .          .
Functional Contracts              8      .         4           .          4
Termination                      11     11         .           .          .
Total                           483     81       398           .      4 (1%)
```

**479 / 483 VCs discharged automatically**, flow analysis clean (0 errors). The
result is identical native vs cross (the 4 unproved are target-independent), but
cross is the correct default and is required for the Tier-B register drivers.

The 4 unproved are the postconditions of `ASR_4 / ASR_8 / ASR32_16 / ASR64_16`
(e.g. `ASR_4'Result = ((X + 1) / 16) - 1`). These relate an *arithmetic shift
right* to integer division, and their bodies are `Shift_Right_Arithmetic`, whose
body is deliberately `SPARK_Mode => Off` (a machine intrinsic). With the
implementation hidden, the prover cannot connect the shift to the division — this
is a known modeling boundary in upstream SPARKNaCl, handled there by
justification, not a toolset defect. Everything that has a SPARK body proves.

**Conclusion:** the local SPARK toolset is working end-to-end and replays
SPARKNaCl. We can proceed to Tier A.
