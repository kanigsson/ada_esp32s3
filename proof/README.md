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
| `x509_proof.gpr` | `X509.DER` + `X509` (parse / `Valid_At` / `Host_Matches`) | **proved** (456/456 VCs) — AoRTE **+ the `Valid_At` functional postcondition** (accept iff both validity times are well-formed and `notBefore ≤ Now ≤ notAfter`); see `tier-a-results.md` |
| `cert_verify_proof.gpr` | `Cert_Verify` (RSA PKCS#1 v1.5 / PSS) | **proved** (0 unproved, `--no-subprojects`) |
| `chain_verify_proof.gpr` | `Chain_Verify` (chain walk, null-safe derefs) | **proved** (63/63 VCs) |
| `aes_gcm_proof.gpr` | `AES.GCM` GHASH authenticator (`GF_Mul`/`GHASH`) | **proved** (17/17 VCs) |
| `net_routes_proof.gpr` | `Net_Routes` (IPv4 longest-prefix routing table) | **proved** (54/54 VCs, 0 justified) — AoRTE **+ `Resolve` functional postcondition** |
| `ftp_replies_proof.gpr` | `FTP_Replies` (FTP reply parsers + PASV `Parse_Pasv`) | **proved** (56/56 VCs, 0 justified) — AoRTE on the attacker-facing parse; found/fixed a PASV overflow bug |
| `ftp_paths_proof.gpr` | `FTP_Paths` (FTP-server path-traversal guard: `Abs_Path` / `Split`) | **proved** (230/230 VCs, 0 justified, 0 warnings) — AoRTE **+ the functional no-escape postcondition** (`No_Parent_Ref (Result)`: normalised output has no `..` component, cannot escape the root) |
| `dns_parse_proof.gpr` | `DNS_Parse` (DNS A-record reply parser: `Skip_Name` + answer-RR walk) | **proved** (41/41 VCs, 0 justified, 0 warnings) — AoRTE on the attacker-facing parse; closes the unbounded `Skip_Name` overrun and the A-record OOB read the inline parse carried |

Tier-A AoRTE is complete across all five attacker-facing units. The networking
layer is now AoRTE-complete too — all four networking targets (`Net_Routes`,
`FTP_Replies`, `FTP_Paths`, `DNS_Parse`) are proved; two of them (`Net_Routes`'s
`Resolve` and `FTP_Paths`'s path-traversal no-escape) go beyond AoRTE to a functional
security property. The reusable proof patterns and the
deferred optional functional properties are recorded in `proof-patterns.md`; the
per-phase VC tables and the AoRTE bugs the proof found are in `tier-a-results.md`.
The next wave of *un-proved* targets (DNS / DHCP / NTP / NMEA / Modbus / ext4 /
P-256) is triaged in `ROADMAP.md`.

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
