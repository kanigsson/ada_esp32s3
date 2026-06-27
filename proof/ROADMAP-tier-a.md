# Tier A roadmap — full proof of the crypto / parsing core

This is the plan for step 3 of the SPARKification effort: take the
**attacker-facing, heap-free, target-portable** units to `SPARK_Mode => On`,
prove **absence of run-time errors (AoRTE)**, and prove **functional
properties** where a clean specification exists. These units parse and verify
hostile network input (X.509 certificates, TLS signatures), so they are the
highest-value proof target and have no hardware dependency that blocks proof.

Prereq: the native proof harness and SPARKNaCl replay (steps 1–2) are in place —
see `README.md`.

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

Add `proof/x509_proof.gpr` following `sparknacl_proof.gpr`: cross-targeted
(`for Target use "xtensa-esp32-elf"`, `for Runtime use Esp32s3_Rts.Runtime_Path`,
`-gnateT=target.atp` via `package Builder`), `Source_Files` listing just these
units plus the **specs** they depend on, driven by `./proof/prove.sh -P
proof/x509_proof.gpr`. Proving against the real target (not native) keeps the
harness uniform with Tier B and faithful to the silicon's representation.

Two dependency subtleties to handle in the GPR:

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

1. **`X509.DER`** — add the `Read` postcondition, fix finding #1, prove AoRTE +
   the postcondition. Smallest unit, unblocks everything.
2. **`X509`** — add `Slice_In` / `Well_Formed`, the `Parse` postcondition,
   consumer preconditions; prove AoRTE. Address findings #2–#4.
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

- `proof/x509_proof.gpr` exists; `gnatprove --report=fail` is silent at
  `--level=2 -j0` for all 5 units (AoRTE).
- `DER.Read`, `Parse` (`Well_Formed`), and `Valid_At` functional postconditions
  proved.
- Finding #1 fixed (with a regression note), findings #2–#4 discharged by
  contracts rather than `pragma Assume` where possible; any residual
  `Assume`/justification documented inline with rationale.
- A short `proof/tier-a-results.md` capturing the VC summary table, mirroring the
  SPARKNaCl section in `README.md`.

## Effort estimate

| Phase | Effort |
|-------|--------|
| Harness GPR + contract-only RSA/SHA wiring | 0.5 day |
| `X509.DER` (+ finding #1) | 0.5 day |
| `X509` (predicate design + AoRTE + `Parse`/`Valid_At` post) | 1.5–2 days |
| `Cert_Verify` AoRTE | 1–1.5 days |
| `Chain_Verify` | 0.5 day |
| `GF_Mul`/`GHASH` AoRTE | 0.25 day |
| `Host_Matches` functional (optional) | +1 day |

~4–6 focused days for AoRTE + the high-value functional postconditions across
the whole certificate-verification path — a fully proven, attacker-facing TLS
cert validator anchored on already-proven SHA-256.
