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

## Phases 2–5 — pending

See `ROADMAP-tier-a.md`: `X509` body (`Parse`/`Valid_At`/`Host_Matches` with the
`Well_Formed` predicate), `Cert_Verify`, `Chain_Verify`, `AES.GCM` GHASH.
