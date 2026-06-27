# Tier A — proof results

Cross-targeted to `xtensa-esp32-elf` (params via `target.atp`), run with
`./proof/prove.sh -P proof/x509_proof.gpr --level=2 -j0`.

## Phase 1 — `X509.DER` (+ `X509` spec)  ✅ complete

`X509.DER` (the DER/ASN.1 TLV reader) is `SPARK_Mode => On` and **fully proved**:
AoRTE + the workhorse postcondition. The parent spec `X509` is `SPARK_Mode => On`
(its body stays Off until phase 2), so the spec's expression functions `Length`
and `Pack_Time` are proved here too.

```
SPARK Analysis results        Total       Flow                              Provers   Unproved
Initialization                    4          4                                    .          .
Run-time Checks                  21          .    21 (CVC5 79%, Z3 19%, altergo 2%)          .
Functional Contracts              1          .    1 (CVC5 29%, Trivial 29%, Z3 43%)          .
Termination                       2          2                                    .          .
Total                            28    6 (21%)                             22 (79%)          .
```

**28 / 28 VCs discharged, 0 unproved, 0 warnings.** No `pragma Assume`, no
justifications.

### The workhorse lemma

`DER.Read`'s postcondition (`x509-der.ads`) — a valid element stays inside
`[Pos .. Limit] ⊆ Buf`, and a non-empty content slice lies within `Buf`:

```ada
Post => (if E.Valid then
           E.Elem_Last <= Limit
           and then E.Elem_Last <= Buf'Last
           and then E.Content.Last <= E.Elem_Last
           and then (if Length (E.Content) > 0 then
                       E.Content.First >= Buf'First
                       and then E.Content.Last <= Buf'Last));
```

This is what phases 2–4 build on: the `X509.Parse` loops walk by re-reading at
`Elem_Last + 1` and index `Buf` over content ranges; the lemma makes that
indexing provably in-bounds.

### Bugs fixed (AoRTE findings the proof forced)

1. **`x509-der.adb` long-form length overflow** (the one flagged in the roadmap).
   `Len := Len * 256 + …` accumulated a 4-byte length in `Natural`, reaching up to
   `2³²-1` and overflowing `Integer` (→ `Constraint_Error`) *before* the
   fit-in-window guard ran. A crafted `84 FF FF FF FF …` cert triggered it.
   **Fix:** accumulate in modular `Unsigned_32` (exact for ≤ 4 bytes, no overflow
   trap), reject lengths the window can't hold, then narrow to `Natural`.

2. **`x509-der.adb` empty-content `P + 1` overflow** (found during the proof, not
   in the original roadmap). The zero-length branch built `Content := (P + 1, P)`;
   `P` can equal `Limit`, so `P + 1` overflows when the buffer ends at the top of
   `Natural`. **Fix:** represent empty content as the canonical empty slice
   `(First => 1, Last => 0)` — no arithmetic, and `Length = 0`.

3. **`x509.ads` `Length` overflow.** `S.Last - S.First + 1` overflows at the index
   type's boundary. **Fix:** index components are now `subtype Buffer_Index is
   Natural range 0 .. Natural'Last - 1` (a slice indexes a finite buffer), so the
   `+ 1` cannot overflow.

4. **`x509.ads` `Pack_Time` overflow.** Unconstrained `Natural` fields could
   overflow `Time_64`. **Fix:** a civil-time precondition (`Year ≤ 9999`, other
   fields `≤ 99`), which the caller (`Parse_Time`, phase 2) already establishes.

A new precondition `Buf'Last < Natural'Last` on `Read` (a cert buffer is not the
whole address space) lets the body prove the bounded-index assignments; phase 2's
`Parse` will carry the matching `Cert'Last < Natural'Last`.

### Regression / compatibility

- `X509.DER` and `X509` compile under the real HAL build (`esp32s3_hal.gpr`,
  embedded, `-gnata -gnat2022`).
- The `Slice` index-type change is source-compatible: full HAL and `libs/tls`
  (`cert_verify`, `chain_verify`, `tls_client`) build unchanged.

## Phase 2 — `X509` body (`Parse` / `Valid_At` / `Host_Matches`)  ✅ complete

The whole parser, validity-date check and hostname matcher are `SPARK_Mode => On`
and **fully proved** — AoRTE plus the `Well_Formed` postcondition on `Parse`.

```
SPARK Analysis results        Total        Flow                             Provers   Unproved
Initialization                   45          45                                   .          .
Non-Aliasing                      1           1                                   .          .
Run-time Checks                  96           .    96 (CVC5 93%, Z3 6%, altergo 1%)          .
Assertions                        6           .                            6 (CVC5)          .
Functional Contracts             61           .    61 (CVC5 86%, Trivial 5%, Z3 9%)          .
Termination                      17          17                                   .          .
Total                           226    63 (28%)                           163 (72%)          .
```

**226 / 226 VCs discharged** (whole `x509_proof.gpr` project: DER + X509), at the
project's default `--level=2`. No justifications; two guiding `pragma Assert`s in
`Parse` (the `TBS` span) that are themselves proved.

### The contract layer

- **`Well_Formed (Cert, C)`** (ghost): every slice a valid `Certificate` carries
  lies within `Cert`, and `SAN_Count <= Max_SAN`. `Parse`'s postcondition; the
  precondition of `Valid_At`, `Host_Matches`, and (phase 3) `Cert_Verify`.
- **`Slice_In`**, **`Indexable`** (ghost) — building blocks: a slice within the
  buffer; a buffer with headroom for one-past-end indices.
- **`Expect`** (the DER-read wrapper) carries a valid/invalid case split and
  `Ok`-monotonicity (`if Ok then Ok'Old`), so a stored slice is provably in-buffer
  whenever the parse ultimately succeeds.
- **`SAN_OK`** invariant + `Loop_Invariant`s drive the SAN-collection loops;
  `Parse_SAN`/`Parse_Extensions` take only the SAN array + count (least privilege),
  so the prover knows the rest of the `Certificate` is preserved.

### SPARK-subset refactors (behaviour-preserving)

- `Parse_Time` was a `Boolean` function with an `out` parameter (not in the SPARK
  subset) → now a procedure with an `Ok` out parameter; `Valid_At` updated.
- The digit reader `D` is made total (a non-digit byte yields 0 instead of
  underflowing `Natural`); nested time-field readers carry `Off < L` bounds.
- `Has_Dot` became a quantified expression function.

Full HAL and `libs/tls` still build (embedded, `-gnata`); `chain_verify` calls
`Valid_At`/`Host_Matches` only after `Parse` + a validity check, so their new
preconditions hold at runtime too.

## Phase 3 — `Cert_Verify` (RSA PKCS#1 v1.5 / PSS)  ✅ complete

`Cert_Verify` (spec + body) is `SPARK_Mode => On` and **fully proved** — AoRTE
across the whole PKCS#1 v1.5 and PSS verification path (the big-endian ⇄ word
conversions, the `PS_Len` / `EmLen` / `DBLen` / `LeadBits` index arithmetic, the
MGF1 mask loop, and the constant-time compares).

Run with `./proof/prove.sh -P proof/cert_verify_proof.gpr -j0 --level=2
--no-subprojects --report=all -u cert_verify.adb`. `cert_verify` discharges with
**0 unproved, 0 warnings**:

```
Check category                  Proved
range check                         72
overflow check                      55
index check                         42
division check                      19
precondition                        14
length check                         6
loop invariant (init + preserv.)     6
assertion                            3
postcondition                        2
loop variant                         1
------------------------------------------
total checks                       255   (0 unproved)
```

(`--no-subprojects` consumes the withed SPARKNaCl by contract only; its library
VCs are proved separately in `sparknacl_proof.gpr` and are out of phase-3 scope.)

### The dependency boundaries (contract-only)

- **`ESP32S3.RSA.Mod_Exp`** — `esp32s3-rsa.ads` is included (spec), the register
  body excluded. The spec carries a `Pre` (modulus-sized, odd, equal lengths) and
  a *shape-only* `Post` (`Z'Length = M'Length`); `Cert_Verify` proves the `Mod_Exp`
  precondition at each call and relies only on the `Post` shape to feed
  `Words_To_BE`. Numeric correctness of the exponentiation is silicon — not proved.
- **`SPARKNaCl.Hashing.SHA256`** — consumed through its (already-proven) contract.
- **`X509`** — only the spec (`Byte_Array` / `U8` types) is needed.

### Bugs / AoRTE findings the proof forced

1. **Empty-modulus negative `'First`.** `M_First : Natural := Modulus'First;`
   failed (`Modulus'First = -1, Modulus'Last = -2` for a null array — gnatprove
   models null-array bounds in the index base type). Added an explicit
   `if Modulus'Length = 0 then return False;` up front (a zero-length modulus can
   never verify), after which `'First` is a provably non-negative index. Done in
   both `RSA_PKCS1_SHA256` and `RSA_PSS_SHA256`.
2. **Signed limb arithmetic in `BE_To_Words`.** The original LSB-walking offset
   `P : Integer := Integer (B'Last) - 4*Idx` could not be proved overflow-free.
   Recast as an unsigned `Base := 4*Idx` from the LSB end (`Idx <= 127` via a loop
   invariant) with guard `Base + k < B'Length` and index `B'Last - Base - k` — all
   `Natural`, provably in `B'Range`. Added `B'Last < Natural'Last - 1` to the Pre.
3. **`Cnt + 1` overflow in the MGF1 loop.** Added the lock-step loop invariant
   `Pos = 32 * Cnt`, which (with `Pos <= Mask_Len + 31`, `Mask_Len <= 4096`) bounds
   `Cnt <= 128` so the block counter cannot overflow.

### Regression / compatibility

- Full `libs/tls/tls.gpr` builds (embedded, `-O2`) — `cert_verify`, `chain_verify`
  and `tls_client` compile unchanged against the new `cert_verify` body. The
  `esp32s3-rsa.ads` `Post` addition leaves the real RSA build green.
- All changes are behaviour-preserving: the empty-modulus early-out reproduces the
  pre-existing `K = 0 ⇒ return False` outcome, and `BE_To_Words` computes the
  identical little-endian words.

## Phase 4 — `Chain_Verify`  ✅ complete

`Chain_Verify` (spec + body) is `SPARK_Mode => On` and **fully proved** — AoRTE
(including **null-safe access dereferences** of every certificate reference) plus
termination of the chain walk. Run with `./proof/prove.sh -P
proof/chain_verify_proof.gpr -j0 --level=2 --report=all`.

```
SPARK Analysis results        Total        Flow                             Provers   Unproved
Initialization                    5           5                                    .          .
Run-time Checks                  40           .                            40 (CVC5)          .
Functional Contracts             10           .    10 (CVC5 91%, Z3 8%, altergo 1%)          .
Termination                       8           8                                    .          .
Total                            63    13 (21%)                            50 (79%)          .
```

**63 / 63 VCs discharged, 0 unproved, 0 warnings** at `--level=2`. The run-time
checks include **17 pointer-dereference checks** (every `Chain (I).Data.all` /
`Anchors (A).Data.all` proven non-null) and the index/precondition checks for the
per-link `Parse` → `Valid_At` / `Host_Matches` / `Sig_OK` calls.

### Contract-only dependency surface (fast run)

`chain_verify_proof.gpr` lists only the **specs** below `Chain_Verify`, so no
bodies — and hence no SPARKNaCl or RSA — are pulled in (the run is seconds, no
`--no-subprojects` needed):

- **`X509`** — `Parse`'s `Well_Formed` postcondition, the `Valid_At` /
  `Host_Matches` preconditions, and the ghost glue (`Indexable` / `Slice_In` /
  `Well_Formed` / `Length`, all expression functions defined in the spec).
- **`Cert_Verify`** — `RSA_PKCS1_SHA256`'s precondition (proved in phase 3).

### The proof shape

- **`All_Parsable (L : Cert_List)`** (ghost, in the spec): every reference is
  non-null and `Indexable`. It is the precondition of `Validate`; real DER buffers
  (a few KiB, library-level aliased) satisfy it, and it lets the body dereference
  and `X509.Parse` each cert without a run-time error. The matching contract glue
  to phases 1–3, lifted to a list of certificates.
- **`Well_Formed` threading.** After each `X509.Parse`, the (checked) `Valid` flag
  gives `Well_Formed` via `Parse`'s postcondition; that flows into `Valid_At`,
  `Host_Matches`, and `Sig_OK` (whose precondition is `Indexable` + `Well_Formed`
  for both the child and issuer buffers).
- **`Sig_OK`** guards `Length (…) >= 1` on the four cert slices before calling
  `RSA_PKCS1_SHA256`, discharging its `TBS'Length >= 1` precondition and tying each
  non-empty slice's `'Last` to the `Indexable` headroom bound.

### Source changes (behaviour-preserving)

1. **Named access type.** `Cert_Ref.Data` changed from an anonymous
   `access constant X509.Byte_Array` (rejected by SPARK as an anonymous-access
   record component) to a named `type Cert_Data is access constant
   X509.Byte_Array`. Source-compatible with the callers' `(Data => X'Access)`
   aggregates.
2. **`Top.Valid` guard.** The anchor loop is wrapped in `if Top.Valid then` after
   the top cert is re-parsed, so `Well_Formed (TB, Top)` is available for `Sig_OK`
   (the main loop already established the top is valid, so behaviour is unchanged).

### Regression / compatibility

`libs/tls/tls.gpr` and the `Chain_Verify` examples (`esp32s3_x509_chain`,
`esp32s3_tls_hello`, `esp32s3_tls_weather`) all build (embedded). The named-access
and precondition changes are transparent at the call sites — the pinned anchors and
received chains are non-null, Indexable buffers, so `All_Parsable` holds at runtime.

## Phase 5 — `AES.GCM` GHASH authenticator  ✅ complete

The GHASH side of AES-GCM — `GF_Mul` (the GF(2¹²⁸) multiply), `GHASH_Block`,
`GHASH_Bytes` and `GHASH_Lengths` — is `SPARK_Mode => On` and **fully proved**
(AoRTE). Run with `./proof/prove.sh -P proof/aes_gcm_proof.gpr -j0 --level=2
--report=all`.

```
SPARK Analysis results        Total       Flow     Provers   Unproved
Initialization                    5          5            .          .
Run-time Checks                  11          .      11 (Z3)          .
Termination                       1          1            .          .
Total                            17    6 (35%)     11 (65%)          .
```

**17 / 17 VCs discharged, 0 unproved, 0 warnings** at `--level=2`. The run-time
checks are the GF(2¹²⁸) bit-loop index/shift arithmetic (`X (I / 8)`,
`Shift_Right (.., I mod 8)`, the 16-byte right-shift+reduce), the GHASH_Bytes block
cursor, and the length-block byte extraction; termination is the GHASH_Bytes
folding loop.

### The hardware boundary (same pattern as RSA)

The AES single-block cipher is the accelerator (silicon), so everything that drives
it is `SPARK_Mode (Off)` and out of scope: `AES_E` (the `Encrypt_ECB` wrapper),
`Inc32`, `CTR`, `Setup`, and the public `Encrypt` / `Decrypt` AEAD entry points.
`aes_gcm_proof.gpr` includes `esp32s3-aes.ads` (the `Block` / `Key_Bytes` /
`Supported_Key` types + the `Encrypt_ECB` contract) but **excludes the register
body** `esp32s3-aes.adb`. The public AEAD API is unchanged.

### Proof note

`GF_Mul` / `GHASH_Block` / `GHASH_Lengths` operate on the fixed 16-byte `Block`, so
their AoRTE is immediate. `GHASH_Bytes` folds a variable-length `Byte_Array` in
16-byte chunks; its only obligation is that the block cursor `Off + 16` not
overflow, discharged by a headroom precondition `Data'Last < Natural'Last - 16`
(real AEAD payloads are a few KiB) — the same "finite buffer" convention as the
X.509 side's `Indexable`. Note this is **AoRTE only**: the algebraic correctness of
`GF_Mul` (carry-less multiply mod x¹²⁸+x⁷+x²+x+1) is a separate, costly functional
proof, deliberately deferred (see `ROADMAP-tier-a.md`, "Functional properties").

### Regression / compatibility

The HAL (`esp32s3_hal.gpr`) and the `esp32s3_aes_gcm_kat` example build (embedded).
The added `GHASH_Bytes` precondition is internal; the `SPARK_Mode (Off)` markers do
not change generated code.

## Tier A — done

AoRTE is proved across all five attacker-facing units: `X509.DER`, `X509`,
`Cert_Verify`, `Chain_Verify`, and the `AES.GCM` GHASH authenticator — anchored on
the already-proven SPARKNaCl SHA-256, with the RSA and AES accelerators consumed by
contract at the silicon boundary. The four proof projects
(`x509_proof.gpr`, `cert_verify_proof.gpr`, `chain_verify_proof.gpr`,
`aes_gcm_proof.gpr`) are all green at `--level=2` with no justifications.
