# SPARK proof patterns & deferred work (crypto / parsing core)

Tier-A AoRTE is **complete** across the five attacker-facing, heap-free units
(`X509.DER`, `X509`, `Cert_Verify`, `Chain_Verify`, `AES.GCM` GHASH) — the
per-phase VC tables and the bugs the proof found are in `tier-a-results.md`, the
harness/toolchain in `README.md`.

This file is the surviving *reference* material: the reusable SPARK patterns the
five phases established (apply them to Tier B/C), the central design moves, how
proof crosses the hardware boundary, and the optional functional properties that
were deliberately deferred.

---

## Units that were in scope

| Unit | Files | LOC | Depends on |
|------|-------|----:|------------|
| `X509.DER` | `x509-der.ads/adb` | ~80 | `Interfaces` only |
| `X509` | `x509.ads/adb` | ~414 | `X509.DER` |
| `Cert_Verify` | `cert_verify.ads/adb` (libs/tls) | ~312 | `X509`, `ESP32S3.RSA` (spec only), `SPARKNaCl.SHA256` |
| `Chain_Verify` | `chain_verify.ads/adb` (libs/tls) | ~125 | `X509`, `Cert_Verify` |
| `ESP32S3.AES.GCM` `GF_Mul`/`GHASH` | part of `esp32s3-aes-gcm.adb` | ~50 | `Interfaces` only |

`SPARKNaCl.Hashing.SHA256` is consumed through its (already-proven) contracts.
`ESP32S3.RSA.Mod_Exp` and the AES block cipher are hardware accelerators consumed
by contract — see "Proving across the hardware boundary" below.

---

## Reusable patterns (proven out in phases 1–5)

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
- **Empty-array `'First` can be negative.** For an unconstrained
  `array (Natural range <>)` formal `B`, gnatprove only knows `B'First`/`B'Last`
  lie in the index *base* type for the **null** case, so `M_First : Natural :=
  B'First;` fails with a counterexample `B'First = -1, B'Last = -2`. Guard with an
  explicit `if B'Length = 0 then return …` before reading `'First` (this is how
  `X509.Parse` is already safe — its `Cert'Length < 2` early-out). Indexing/slicing
  `B (B'First)` proves regardless (it uses `B'Range`, which is tautological); only
  *storing* a bound into a `Natural` needs the non-empty guard.
- **Keep big-int limb arithmetic in `Natural`, not signed `Integer`.**
  `BE_To_Words`' `P := Integer (B'Last) - 4*Idx` (a byte offset that walks off the
  low end) defeated the overflow prover even with `Idx <= 127`. Recast as an
  unsigned offset `Base := 4*Idx` from the LSB end with guard `Base + k < B'Length`
  and index `B'Last - Base - k`: every subtraction is then provably `>= B'First`.
- **Named access-to-constant, never anonymous.** A record component
  `Data : access constant Byte_Array` is rejected by SPARK ("component of anonymous
  access type"). Declare a named `type Cert_Data is access constant Byte_Array;` —
  source-compatible with callers' `(Data => X'Access)` aggregates. Dereferences
  then prove null-safe from a precondition `Data /= null` (here folded into a
  ghost `All_Parsable` quantified over the `Cert_List`, alongside `Indexable`).
- **Re-assert `Valid` after a re-`Parse` to recover `Well_Formed`.**
  `Chain_Verify` re-parses the top cert for the anchor loop; even though the main
  loop already proved it valid, the prover needs an explicit `if Top.Valid then`
  around the re-parse to re-derive `Well_Formed (TB, Top)` for the `Sig_OK` call.
  Same move as threading `Parse`'s `Post` through each link's consumers.
- **Guard a contract's length precondition at the call.** `Sig_OK` feeds
  cert slices to `RSA_PKCS1_SHA256` (which needs `TBS'Length >= 1`). Rather than
  strengthen `Well_Formed`, short-circuit on `Length (Child.TBS) >= 1 and then …`:
  it discharges the callee precondition and, for a *non-empty* slice, ties the
  slice's `'Last` to `buffer'Last` (hence to the `Indexable` headroom bound). A
  cert missing the field can't carry a signature, so the `False` result is correct.

---

## The central design move: an "in-buffer" predicate

Every consumer of a parsed `Certificate` indexes the original `Cert` buffer
through the slices in the record (`Valid_At`, `Host_Matches`, and `Cert_Verify`
via the `RSA_Modulus` / `Signature` / `TBS` slices). AoRTE for those consumers
is impossible unless the prover knows **every slice in a valid `Certificate`
lies within `Cert'Range`** and `SAN_Count <= Max_SAN`.

A ghost predicate, threaded as the `Parse` postcondition and the consumers'
precondition, supplies exactly that:

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
holds `access constant Byte_Array` refs, so it re-asserts `Well_Formed` after
each `Parse` and passes it into `Cert_Verify`.

## Workhorse lemma: `DER.Read`

Everything rests on one postcondition — a valid element stays inside
`[Pos .. Limit] ⊆ Buf`:

```ada
procedure Read (Buf : Byte_Array; Pos, Limit : Natural; E : out TLV)
  with Post =>
    (if E.Valid then
        E.Content.First >= Buf'First and then E.Elem_Last <= Limit
        and then E.Content.Last <= E.Elem_Last
        and then E.Elem_Last <= Buf'Last);
```

Once `Read` guarantees that, the `Parse` loops (`P := E.Elem_Last + 1`, the
SAN/extension walks) prove their indexing inductively, and `Well_Formed` falls
out. A `Buf'Last < Natural'Last` precondition (a cert buffer is not the whole
address space) discharges the bounded-index `+1` assignments.

---

## Proving across the hardware boundary

Two units the verification path calls are silicon (register-level accelerators).
Their bodies stay `SPARK_Mode => Off`; proof consumes their **specs by contract**:

1. **`ESP32S3.RSA.Mod_Exp`.** Include `esp32s3-rsa.ads` (contracts) but **exclude
   `esp32s3-rsa.adb`** (register body). gnatprove treats `Mod_Exp` as
   contract-only: callers rely on its `Pre`/`Post`. The spec carries a `Pre`
   (modulus-sized, odd, equal lengths) and a *shape-only* `Post` (`Z` fully
   initialised, `Z'Length = M'Length`) so `Words_To_BE (Z, …)` proves —
   correctness of the modular exponentiation itself is not provable here (it is
   silicon) and is out of Tier-A's functional scope. (`cert_verify_proof.gpr`.)
2. **The AES single-block cipher.** `aes_gcm_proof.gpr` includes `esp32s3-aes.ads`
   (the `Block`/`Key_Bytes`/`Supported_Key` types + the `Encrypt_ECB` contract)
   but **excludes** `esp32s3-aes.adb`. Everything that drives the cipher
   (`AES_E`, `Inc32`, `CTR`, `Setup`, the public `Encrypt`/`Decrypt` AEAD entry
   points) is `SPARK_Mode (Off)`; only the GHASH authenticator is proved.
3. **`SPARKNaCl.Hashing.SHA256`** is consumed through its (already-proven)
   contract — `--no-subprojects` on `cert_verify_proof.gpr` keeps gnatprove from
   re-proving the whole library (which would time out).

The proof projects are cross-targeted to `xtensa-esp32-elf` (params via
`target.atp`), `with` only the specs below the unit under proof, and deliberately
do **not** pull in the runtime's `build_libgnat`/`build_libgnarl` (that makes
`gnat2why` analyse the whole runtime and crash). See `README.md`.

---

## Deferred / optional: functional properties

AoRTE is proved everywhere. *Functional* proof (needs a clean spec, sometimes
infeasible) was scoped down to what carries its weight; the rest is deferred:

| Property | Feasible? | Status / notes |
|----------|-----------|----------------|
| AoRTE across all 5 units | **Yes** | ✅ done — the core Tier-A deliverable |
| `DER.Read`: valid ⇒ element within window | **Yes** | ✅ done — the workhorse lemma |
| `Parse`: valid ⇒ `Well_Formed` | **Yes** | ✅ done — falls out of the lemma |
| `Valid_At` ⇔ `notBefore ≤ Now ≤ notAfter` | **Yes** | clean spec via `Pack_Time`; AoRTE done, functional spec optional |
| `Host_Matches` implements RFC 6125 matching | **Partial / spec-heavy** | ⬜ deferred — provable but the wildcard spec is fiddly; ~1 day |
| `GF_Mul` = carry-less mult mod x¹²⁸+x⁷+x²+x+1 | **Yes but costly** | ⬜ deferred — needs a `Ghost` polynomial-arithmetic spec; high effort/value ratio |
| `RSA_PKCS1/PSS` = "signature valid ⇔ …" | **No (by design)** | rests on `Mod_Exp` correctness, which is hardware. AoRTE + the constant-time-compare structural property are proved; functional RSA correctness is a documented silicon assumption |
