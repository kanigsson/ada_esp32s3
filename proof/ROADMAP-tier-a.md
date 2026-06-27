# Tier A roadmap — full proof of the crypto / parsing core

This is the plan for step 3 of the SPARKification effort: take the
**attacker-facing, heap-free, target-portable** units to `SPARK_Mode => On`,
prove **absence of run-time errors (AoRTE)**, and prove **functional
properties** where a clean specification exists. These units parse and verify
hostile network input (X.509 certificates, TLS signatures), so they are the
highest-value proof target and have no hardware dependency that blocks proof.

Prereq: the cross-targeted proof harness and SPARKNaCl replay (steps 1–2) are in
place — see `README.md`.

---

## ▶ STATUS & HANDOFF (read this first)

| Phase | Unit | State |
|------:|------|-------|
| 1 | `X509.DER` | ✅ **proved** (AoRTE + `Read` lemma) |
| 2 | `X509` body (`Parse`/`Valid_At`/`Host_Matches`) | ✅ **proved** (AoRTE + `Well_Formed`) |
| 3 | `Cert_Verify` (RSA PKCS#1 v1.5 / PSS) | ⬜ **next — start here** |
| 4 | `Chain_Verify` | ⬜ pending |
| 5 | `AES.GCM` `GF_Mul`/`GHASH` | ⬜ pending (independent, easy) |

`proof/x509_proof.gpr` proves at **226/226 VCs, `--level=2`, no justifications**
(full results + per-phase tables in `tier-a-results.md`).

**How to run** (toolchain/env is all handled by the script):
```sh
./proof/prove.sh -P proof/x509_proof.gpr -j0 --report=fail   # all proved => silent
./proof/prove.sh -P proof/x509_proof.gpr -j0 --report=all -u <unit>.adb   # per-unit detail
```
Bump `--level=3`/`4` while iterating; the committed proof holds at the gpr default
`--level=2`. Don't hand-set `PATH`/`target.atp` — `prove.sh` does it.

### Phase 3 starting steps (`Cert_Verify`, in `libs/tls`)

1. Add a proof project `proof/cert_verify_proof.gpr` mirroring `x509_proof.gpr`,
   but with `Source_Dirs` covering both `../libs/esp32s3_hal/src` and
   `../libs/tls/src`. `Source_Files`: `cert_verify.ads/adb`, `x509.ads`,
   `x509-der.ads`, the **SPARKNaCl** sources it needs (`with` or add
   `../crates/sparknacl/src`), and `esp32s3-rsa.ads` **only** (see step 3).
2. Turn `Cert_Verify` `SPARK_Mode => On`. Prove **AoRTE** across the PKCS#1 / PSS
   index arithmetic (`PS_Len`, `EmLen`, `DBLen`, `ZeroN`, `2 ** (8-LeadBits)`,
   the `BE_To_Words`/`Words_To_BE` loops).
3. **Proving across the hardware boundary** (see section below): include
   `esp32s3-rsa.ads` but **exclude `esp32s3-rsa.adb`** (register body). Add a
   `Post` to `ESP32S3.RSA.Mod_Exp` describing the result *shape* only
   (`Z'Length = M'Length`, `Z` initialised) so `Words_To_BE (Z, …)` proves —
   correctness of the modular exponentiation is silicon, out of scope.
4. Consume the proven `X509` results: `Cert_Verify`'s callers slice the buffer
   over `Certificate` fields, so thread `X509.Well_Formed` (already a postcondition
   of `Parse`) into the relevant preconditions — do **not** re-derive bounds.
5. Scope: **AoRTE + constant-time-compare structural property**, not functional
   "signature valid ⇔ …" (rests on `Mod_Exp` = hardware). See the table in
   "Functional properties" below.

### Reusable patterns established in phases 1–2 (apply these in 3–5)

- **In-buffer contract glue** lives in `x509.ads` (ghost): `Slice_In`,
  `Well_Formed`, `Indexable` (buffer leaves one-past-end headroom: `Cert'Last <
  Natural'Last - 1`). Reuse them; don't invent parallel predicates.
- **Case-split postconditions beat unconditional ones.** A flat
  `E.Elem_Last <= Buf'Last` would not prove; `(if Valid then … else Elem_Last = 0)`
  did. When a fact has a trivial "failure" value, state it as a case split.
- **Least-privilege parameters.** Pass the specific components a helper mutates
  (e.g. `SAN : in out Slice_Array; Count : in out Natural`), not the whole record,
  so the prover knows untouched fields are preserved across the call.
- **Monotone status flags:** an `Ok : in out Boolean` wrapper with
  `Post => (if Ok then Ok'Old)` lets you prove "a value stored mid-walk is good
  whenever the walk ultimately succeeds."
- **SPARK subset gotcha:** a `Boolean` function with an `out` parameter is **not**
  in the subset — make it a procedure (cost me a refactor of `Parse_Time`).
- **Total accessors:** make digit/byte readers total (return 0 for out-of-domain)
  to kill underflow VCs instead of threading value preconditions everywhere.

---

## Units in scope

| Unit | Files | LOC | Depends on |
|------|-------|----:|------------|
| `X509.DER` | `x509-der.ads/adb` | ~80 | `Interfaces` only |
| `X509` | `x509.ads/adb` | ~414 | `X509.DER` |
| `Cert_Verify` | `cert_verify.ads/adb` (libs/tls) | ~312 | `X509`, `ESP32S3.RSA` (spec only), `SPARKNaCl.SHA256` |
| `Chain_Verify` | `chain_verify.ads/adb` (libs/tls) | ~125 | `X509`, `Cert_Verify` |
| `ESP32S3.AES.GCM` `GF_Mul`/`GHASH` | part of `esp32s3-aes-gcm.adb` | ~50 | `Interfaces` only |

`SPARKNaCl.Hashing.SHA256` is **already proven** — we consume it through its
contracts. `ESP32S3.RSA.Mod_Exp` is the hardware accelerator: its body touches
registers and stays `SPARK_Mode => Off`, but its **spec already carries the
`Pre` contracts we need** (`x509-rsa.ads`), so `Cert_Verify` is proved against
the RSA *spec* with the body excluded/stubbed. See "Proving across the hardware
boundary" below.

## How proof is wired (cross-targeted, contract-only deps)

`proof/x509_proof.gpr` (phases 1–2) is the template: cross-targeted
(`for Target use "xtensa-esp32-elf"`, `for Runtime use Esp32s3_Rts.Runtime_Path`,
`-gnateT=target.atp` via `package Builder`), with `Source_Files` listing just the
units under proof plus the **specs** they depend on, driven by `./proof/prove.sh
-P proof/x509_proof.gpr`. Proving against the real target (not native) keeps the
harness uniform with Tier B and faithful to the silicon's representation. The
phase-3 `Cert_Verify` project follows the same shape (see the handoff above).

Two dependency subtleties to handle in each GPR:

1. **`Cert_Verify` → `ESP32S3.RSA`.** Include `esp32s3-rsa.ads` (contracts) but
   **exclude `esp32s3-rsa.adb`** (register body). gnatprove treats `Mod_Exp` as
   a contract-only subprogram: callers rely on its `Pre`/`Post`. Today the RSA
   spec has only `Pre`; add a `Post` describing the *shape* of the result (`Z`
   fully initialised, `Z'Length = M'Length`) so `Words_To_BE (Z, ...)` proves —
   correctness of the modular exponentiation itself is not provable here (it is
   silicon) and is out of Tier A's functional scope.
2. **`Cert_Verify` → `SPARKNaCl`.** Add SPARKNaCl's `src` to the proof project's
   path (or `with` the `sparknacl_proof.gpr`). SHA256's contracts already hold.

## The central design move: an "in-buffer" predicate

Every consumer of a parsed `Certificate` indexes the original `Cert` buffer
through the slices in the record (`Valid_At`, `Host_Matches`, and `Cert_Verify`
via the `RSA_Modulus` / `Signature` / `TBS` slices). AoRTE for those consumers
is impossible unless the prover knows **every slice in a valid `Certificate`
lies within `Cert'Range`** and `SAN_Count <= Max_SAN`.

Introduce a ghost predicate and thread it as the `Parse` postcondition and the
consumers' precondition:

```ada
--  in x509.ads
function Slice_In (Cert : Byte_Array; S : Slice) return Boolean is
  (S.Last < S.First                                  --  empty slice: always ok
   or else (S.First >= Cert'First and then S.Last <= Cert'Last))
with Ghost;

function Well_Formed (Cert : Byte_Array; C : Certificate) return Boolean is
  (C.SAN_Count <= Max_SAN
   and then Slice_In (Cert, C.TBS)
   and then Slice_In (Cert, C.Serial)
   and then Slice_In (Cert, C.Not_Before)
   and then Slice_In (Cert, C.Not_After)
   and then Slice_In (Cert, C.Signature)
   and then Slice_In (Cert, C.RSA_Modulus)
   and then Slice_In (Cert, C.RSA_Exponent)
   and then (for all I in 1 .. C.SAN_Count => Slice_In (Cert, C.SAN (I))))
with Ghost;

procedure Parse (Cert : Byte_Array; Result : out Certificate)
  with Post => (if Result.Valid then Well_Formed (Cert, Result));

function Valid_At (Cert : Byte_Array; C : Certificate; Now : Time_64)
  return Boolean with Pre => Well_Formed (Cert, C);

function Host_Matches (Cert : Byte_Array; C : Certificate; Host : String)
  return Boolean with Pre => Well_Formed (Cert, C);
```

`Well_Formed` becomes the contract glue across the whole chain: `Chain_Verify`
already holds `access constant Byte_Array` refs, so it can re-assert
`Well_Formed` after each `Parse` and pass it into `Cert_Verify`.

## Workhorse lemma: `DER.Read`

Everything rests on one postcondition. Give `DER.Read` a contract that the rest
of the parser can lean on:

```ada
procedure Read (Buf : Byte_Array; Pos, Limit : Natural; E : out TLV)
  with Post =>
    (if E.Valid then
        E.Content.First >= Buf'First and then E.Elem_Last <= Limit
        and then E.Content.Last <= E.Elem_Last
        and then E.Elem_Last <= Buf'Last);
```

Once `Read` guarantees "a valid element stays inside `[Pos .. Limit] ⊆ Buf`",
the `Parse` loops (`P := E.Elem_Last + 1`, the SAN/extension walks) prove their
indexing inductively, and `Well_Formed` falls out.

## Concrete findings already visible (fix during the AoRTE pass)

These are the spots where proof will *fail first* — i.e. real or latent issues
the proof forces you to address:

1. **Overflow in long-form length decode — `x509-der.adb:40`.**
   `Len := Len * 256 + Natural (Buf (P + K));` with `NBytes` up to 4 can reach
   `2³²-1`, which overflows `Natural` (`Integer'Last = 2³¹-1`) *before* the
   `Len > Limit - P` guard on line 51 runs. A 5-byte buffer with a crafted
   `84 FF FF FF FF` length triggers `Constraint_Error` today.
   **Fix:** decode into `Interfaces.Unsigned_32`/`Long_Long_Integer` and reject
   `Len` that exceeds the window before narrowing to `Natural`; or cap `NBytes`
   at 3 (cert buffers are far below 16 MiB). gnatprove's overflow check on this
   line is the trigger.

2. **Index `+1` near `Natural'Last`.** `E.Elem_Last + 1`, `Bits.Content.First +
   1`, `S.First + 1/2` (e.g. `x509.adb:113,163,202,316,328`). Safe in practice
   (buffers are small) but the prover needs to know it. The `DER.Read`
   postcondition (`Elem_Last <= Buf'Last`) plus a sane buffer-length bound makes
   these provable; otherwise add `Pre => Cert'Last < Natural'Last`.

3. **Slices used after a failed `Expect`.** `Parse` stores `E.Content` even on
   the failure path (e.g. `x509.adb:118,138`). It is *currently* safe because
   `Expect` resets `E` to an empty slice on failure, but the proof makes that
   reasoning explicit — confirm `Expect`'s postcondition states
   `not Ok'Result_in => E.Valid = False and Slice empty`.

4. **`Parse_Time` field indexing — `x509.adb:225,232`.** `Cert (F + Off)` for
   `Off` up to 14. Guarded by the `L /= 13/15` length checks, but those bound
   `Length(S)`, not `S` against `Cert'Range` — needs `Well_Formed` in the
   precondition (it is called only via `Valid_At`, which will have it).

## Proof phases & ordering

Bottom-up, each phase green before the next:

1. **`X509.DER`** ✅ **DONE** (see `tier-a-results.md`) — `SPARK_Mode On`, `Read`
   postcondition added and proved, AoRTE clean (28/28 VCs). Fixed the long-form
   length overflow (finding #1), plus three more the proof surfaced: an empty-
   content `P+1` overflow, and `Length`/`Pack_Time` overflows in the `X509` spec.
   The `X509` spec is now `SPARK_Mode On` (body Off until phase 2).

2. **`X509`** ✅ **DONE** (see `tier-a-results.md`) — whole body `SPARK_Mode On`,
   AoRTE + `Well_Formed` postcondition on `Parse`, preconditions on `Valid_At`/
   `Host_Matches`. The full `x509_proof.gpr` project proves at 226/226 VCs. Built
   the `Well_Formed`/`Slice_In`/`Indexable`/`SAN_OK` contract layer; refactored
   `Parse_Time` out of the non-subset "function with `out` parameter" shape.

3. **`Cert_Verify`** — wire the contract-only RSA/SHA deps; prove AoRTE across
   the PKCS#1 / PSS index arithmetic (the `PS_Len`, `EmLen`, `DBLen`, `2 **
   (8-LeadBits)` computations). Add the RSA spec `Post` (shape only).
4. **`Chain_Verify`** — prove the chain walk terminates and re-establishes
   `Well_Formed` per link; AoRTE.
5. **`AES.GCM` `GF_Mul`/`GHASH`** — independent; AoRTE is trivial (fixed 16-byte
   arrays). Optional functional spec below.

## Functional properties: what is realistically provable

Distinguish AoRTE (always achievable here) from *functional* proof (needs a
spec, sometimes infeasible):

| Property | Feasible? | Notes |
|----------|-----------|-------|
| AoRTE across all 5 units | **Yes** | the core Tier-A deliverable |
| `DER.Read`: valid ⇒ element within window | **Yes** | the workhorse lemma |
| `Parse`: valid ⇒ `Well_Formed` | **Yes** | falls out of the lemma |
| `Valid_At` ⇔ `notBefore ≤ Now ≤ notAfter` | **Yes** | clean spec via `Pack_Time` |
| `Host_Matches` implements RFC 6125 matching | **Partial / spec-heavy** | provable but the wildcard spec is fiddly; do it after the rest is green |
| `GF_Mul` = carry-less mult mod x¹²⁸+x⁷+x²+x+1 | **Yes but costly** | needs a `Ghost` polynomial-arithmetic spec; high effort/value-ratio — recommend AoRTE + a bit-level loop-invariant postcondition, defer full algebraic proof |
| `RSA_PKCS1/PSS` = "signature valid ⇔ …" | **No (by design)** | rests on `Mod_Exp` correctness, which is hardware (`SPARK_Mode Off`). Prove AoRTE + the **constant-time compare** structural property; functional correctness of RSA is a silicon assumption, document it as such |

## Definition of done (Tier A)

- ✅ `proof/x509_proof.gpr` exists; `--report=fail` silent at `--level=2 -j0`
  (phases 1–2: `X509.DER` + `X509`, 226/226 VCs).
- ✅ `DER.Read`, `Parse` (`Well_Formed`) functional postconditions proved.
  (`Valid_At`/`Host_Matches` proved AoRTE; their *functional* date/RFC-6125 specs
  are optional, see below.)
- ✅ Finding #1 fixed plus three more the proof surfaced (empty-content `P+1`,
  `Length`, `Pack_Time`); all discharged by contracts, no `pragma Assume`. The
  two `pragma Assert`s in `Parse` (TBS span) are themselves proved.
- ✅ `proof/tier-a-results.md` captures the per-phase VC summary tables.
- ⬜ Remaining for Tier A done: phase 3 `Cert_Verify`, phase 4 `Chain_Verify`,
  phase 5 `AES.GCM` GHASH (each its own proof GPR + `tier-a-results.md` section).

## Effort estimate

| Phase | Effort | Status |
|-------|--------|--------|
| Harness GPR + SPARKNaCl replay | 0.5 day | ✅ done |
| `X509.DER` (+ finding #1) | 0.5 day | ✅ done |
| `X509` (predicate design + AoRTE + `Parse` post) | 1.5–2 days | ✅ done |
| `Cert_Verify` AoRTE | 1–1.5 days | ⬜ next |
| `Chain_Verify` | 0.5 day | ⬜ |
| `GF_Mul`/`GHASH` AoRTE | 0.25 day | ⬜ |
| `Host_Matches` functional (optional) | +1 day | ⬜ optional |

~4–6 focused days for AoRTE + the high-value functional postconditions across
the whole certificate-verification path — a fully proven, attacker-facing TLS
cert validator anchored on already-proven SHA-256.
