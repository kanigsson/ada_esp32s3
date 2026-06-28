# Roadmap — proving the networking layer (post-merge targets)

Tier A (the crypto / X.509 certificate-verification core) is proved end-to-end —
see `proof-patterns.md` and `tier-a-results.md`. The 2026-06 upstream merge
(rowsail `880af4d → 27790e9`) then added a sizeable networking layer: an FTP
client and server, an IPv4 route table, a `GNAT.Sockets` routing facade, an ext4
VFS, and a TLV2556 SPI ADC driver. None of it has been analysed for SPARK yet.

This roadmap triages that new code against the project's proof profile
(**attacker-facing, heap-free, no controlled types / `Ada.Finalization`, no
secondary stack, target-portable**) and orders the work by value-per-effort. It
is a *static* triage from reading the sources — no gnatprove run yet; the first
action below is to confirm target #1 actually proves.

The proof mechanics (cross-target via `target.atp`, contract-only deps, the
in-buffer-predicate / workhorse-lemma patterns, the hardware boundary) are all in
`proof-patterns.md` — reuse them; this file only records *what* to prove and *why*.

---

## ▶ STATUS

| # | Target | Tier | State |
|--:|--------|------|-------|
| 1 | `Net_Routes` (whole package) | A-profile (AoRTE **+ functional**) | ✅ **proved** — AoRTE + `Resolve` functional postcondition, 54/54 VCs, 0 justified |
| 2 | FTP client reply parsers (now `FTP_Replies`) | A-profile (AoRTE) | ✅ **proved** — factored out + AoRTE, 56/56 VCs, 0 justified; found & fixed a PASV overflow bug |
| 3 | FTP server path resolution (now `FTP_Paths`: `Abs_Path` / `Split`) | A-profile (AoRTE **+ functional no-escape**) | ✅ **proved** — refactored into a pure bounded-buffer unit; AoRTE **+ the functional no-escape postcondition** (`No_Parent_Ref (Result)`: the normalised path holds no `..` component, so it cannot climb above the root), 230/230 VCs, 0 unproved / 0 justified / 0 warnings |
| — | TLV2556 + SPI/`*-engine` / `w25q` / `w5500` / `sd_spi` churn | B (register drivers) | ⬜ folds into the existing Tier-B bucket |
| — | Socket-coupled FTP flow, `gnat-sockets`, `ext4-vfs` | C (`SPARK_Mode Off`) | n/a — controlled handles, out of subset |

---

## 1. `Net_Routes` — the standout new target ⭐ ✅ PROVED

`libs/esp32s3_hal/src/net_routes.{ads,adb}`, ~150 LOC. The cleanest SPARK target
to land since `X509.DER`.

**Result (2026-06-28).** `proof/net_routes_proof.gpr` at `--level=2`: **54/54 VCs
discharged, 0 unproved, 0 justified**, flow analysis clean. AoRTE *and* the full
`Resolve` functional postcondition (longest-prefix, then lowest-metric; `Found`
iff a route qualifies). The host test (`test/net_routes/`) still passes 9/9 —
the proof refactor is behaviour-preserving. What it took, all minor:
- `Prefix_Len`: rewrote the `while V /= 0` popcount as a bounded `for I in 0 .. 31`
  scan with invariant `N <= I + 1`, so the `N + (bit)` add is provably bounded
  (the while-loop gave the prover no iteration cap → an overflow VC).
- `N_Routes`: constrained to `subtype Route_Count is Natural range 0 .. Max_Routes`
  so `Table (I)` indexing proves (the `Add_Route` guard already maintained it).
- `Resolve`: a ghost `Qualifies (R, D, Live)` predicate + a best-so-far loop
  invariant carrying a **ghost `Witness` index** that backs `(Iface, Best_Len,
  Best_Metric)`, stated as a `Refined_Post` over the body state.
- **The `Up` callback wrinkle, resolved cleanly (0 justified).** The indirect call
  `Up (Iface)` has no visible body, so an *expression function* that calls it can't
  discharge its implicit `Always_Terminates`. Fix: `Qualifies` takes liveness as a
  `Live : Boolean` parameter (trivially terminating); the `Up = null or else
  Up (..)` call lives only in `Resolve`'s assertions/contract, which carry no
  termination obligation. See the new note in `proof-patterns.md`.

**Why it's ideal**
- **Pure logic, no obstacles.** A bounded `array (1 .. 16) of Route`, bit-twiddling
  (`U32`, `Prefix_Len` popcount), and a longest-prefix + lowest-metric selection in
  `Resolve`. No heap, no `Ada.Finalization`, no secondary stack, no `return String`.
- **Already built to be pure and host-testable** — liveness is injected via
  `Configure (Is_Up : Up_Query)` rather than wired to a stack, and there is a mock
  up-state harness in `test/net_routes/`. The author effectively pre-shaped it for
  proof.
- **Goes beyond AoRTE to functional proof.** `Resolve`'s contract is clean and
  worth stating as a postcondition, not just discharging run-time checks:
  > among routes whose destination matches `Dest` *and* whose interface is up,
  > the chosen `Iface` has the longest prefix; ties are broken by lowest metric;
  > `Found = False` iff no route qualifies.
  This is a genuine functional property over a small state space — rare and
  high-value. Provable with a loop invariant tracking "best-so-far is the
  longest/lowest among `Table (1 .. I)`".

**The one wrinkle**
- `Up_Query` is an `access function (Id) return Boolean` called as `Up (R.Iface)`.
  SPARK supports access-to-subprogram, but the indirect call needs handling — give
  the access type a contract (or treat `Up`'s result as unconstrained and prove
  around it). The `Up = null` short-circuit is already there, so null-safety is
  trivial.

**Plan** (all done)
1. ✅ Added `proof/net_routes_proof.gpr` mirroring the contract-only template
   (`Source_Files`: `net_routes.ads/adb`, `net_devices.ads`; cross-targeted).
2. ✅ Flow + AoRTE at `--level=2` — clean after the three minor fixes above.
3. ✅ Added the `Resolve` functional postcondition + best-so-far loop invariant.

**Effort: came in roughly as estimated (~0.5 day AoRTE, +0.5 day functional).**

---

## 2. FTP client reply parsers — the attacker-facing parse ✅ PROVED

**Result (2026-06-28).** Factored the pure parsing out of `ftp_client.adb` into a
new standalone `FTP_Replies` (`ftp_replies.{ads,adb}`, depends only on `Interfaces`)
and proved it: `proof/ftp_replies_proof.gpr` at `--level=2`, **56/56 VCs, 0 unproved,
0 justified**. The `FTP_Client` body now `with`s it (`Open_Passive` calls
`Parse_Pasv`); the FTP host test still passes 12/12 against a live Python server, so
the refactor is behaviour-preserving.

- **AoRTE on the reply-line helpers** (`Code_Of`, `Is_Mid_Multiline`,
  `Is_Final_Line`) — shared `Pre => Last <= Line'Length`; index values held in the
  index base type (`Integer`), per the "empty-array `'First`" pattern.
- **`Parse_Pasv` (the security-relevant one) — and a real bug it found.** The inline
  parse accumulated each field as `Nums (Slot) := Nums (Slot) * 10 + digit` with **no
  bound**, and then built `Port_Type (Nums (5) * 256 + Nums (6))`. A hostile/buggy
  `227` reply with a long digit run **overflows** `Natural` (and the `Port_Type`
  conversion) → `Constraint_Error` on the board. The proved parser caps each field
  (`<= 255` guard, so a field tops out at 2559 — no overflow) and **fails closed**
  (`Ok := False`) on any field `> 255`, a missing field, or no parenthesised group;
  the port is then provably `<= 65535` and every index provably in range. Postcondition
  also pins the failure shape (`not Ok` ⇒ `Host`/`Port` zeroed).

**Refactor done:** `Parse_Pasv (Line, Last; Host, Port, Ok)` is now a pure
`SPARK_Mode On` procedure in `FTP_Replies`; the socket-opening `Open_Passive` stays
in the (unproved, socket-coupled) `FTP_Client` body and just calls it.

The original triage notes are kept below for reference.

`libs/esp32s3_hal/src/ftp_client.adb`. The socket-driving outer layer
(`Connect` / `Retrieve` / `Store`, the `Session` over `GNAT.Sockets.Socket_Type`)
is **Tier C** — `GNAT.Sockets` uses controlled handles, out of the subset. But the
reply parsing is pure `String`/`Natural` work over **hostile server input** and is
the same in-buffer shape as `X509.DER`:

- `Code_Of (Line, Last) return Integer` — the 3-digit reply code.
- `Is_Mid_Multiline (Line, Last)` / `Is_Final_Line (Line, Last, Code)` — RFC 959
  multiline-reply framing.
- **The PASV octet parser inside `Open_Passive`** — extracts the `h1,h2,h3,h4,p1,p2`
  address+port from the `227 (...)` reply. This is the genuinely security-relevant
  one: the client then *dials* that address, so a malicious or buggy server controls
  where it connects. Worth proving the extraction can't index out of range or
  overflow the port (`p1*256 + p2`).

**Refactor needed:** the PASV parse is currently inline in `Open_Passive` (which
also opens the socket). Factor the byte-extraction into a pure
`Parse_Pasv (Line, Last; Host : out ...; Port : out ...; Ok : out Boolean)` helper,
mark it `SPARK_Mode On`, and prove AoRTE on it + the reply-line helpers. The outer
`Open_Passive` stays `SPARK_Mode Off`.

**Value: medium-high (the PASV parser is real attacker surface). Effort: small once
factored.**

---

## 3. FTP server path resolution — highest security relevance ✅ PROVED (AoRTE + no-escape)

**Result (2026-06-28).** Factored the pure path handling out of `ftp_server.adb`
into a new standalone `FTP_Paths` (`ftp_paths.{ads,adb}`, touches only
`String`/`Natural`/`Integer` — never the VFS or `GNAT.Sockets`) and proved it:
`proof/ftp_paths_proof.gpr` at `--level=2`, **230/230 VCs, 0 unproved, 0 justified,
0 warnings**, flow analysis clean. This now includes the **functional no-escape
postcondition**, not just AoRTE.

**Functional no-escape contract (the path-traversal guarantee), proved.**
`Abs_Path`'s postcondition now carries `No_Parent_Ref (Result (..))`: the
normalised output contains no complete `..` path component, so a hostile
`"../../../etc"` provably cannot climb above the root. The proof rests on three
pieces in `ftp_paths.{ads,adb}`:
- ghost predicates `Dot_Dot_At (S, K)` (a complete `..` component — two dots
  bounded by `/` or the string ends) and `No_Parent_Ref (S)` (no such `K`);
- a component-walk loop invariant `No_Parent_Ref (O (1 .. OLen))` carried through
  every iteration — the `.`/append cases trivially preserve it (append adds a
  single `/`-free name), and
- a ghost lemma `Lemma_Trunc_Keeps_No_Parent (S, N, M)` for the `..` pop: it shows
  truncating a no-`..` path on a component boundary (the bare root, or just before
  a `/`) keeps the property, because any `..` newly exposed in the prefix would
  already have been a `..` in the full path — contradicting the hypothesis.

The deeper cosmetic normalisation (output also free of `.`/`//`) is not
security-relevant and stays optional.

- `Abs_Path` (125 checks) — the path-traversal guard: normalises a client-supplied
  `Arg` against `Cwd` into a caller-supplied buffer, collapsing `"."` / `".."` /
  `"//"` / trailing `"/"`. The component walk applies every `".."` against the
  output cursor, which can never back up past the leading `"/"`, so a hostile
  `"../../../etc"` resolves back to `"/"`. The proof rests on a *keyed* loop
  invariant relating the output cursor to the input cursor —
  `OLen <= I - 1 - (1 if O (OLen) /= '/')` — funded by the leading `'/'` that is
  copied but never re-counted; this is what bounds every output index write.
- `Split` (35 checks) — breaks an absolute path into (parent dir, last name) by
  scanning for the last `'/'`.
- Both write into caller-supplied buffers (no `return String` / secondary stack),
  the same bounded-buffer shape that took `Parse_Time` into the subset in Tier A —
  the refactor this section anticipated.

**Scope: AoRTE** (+ the spec's rooted-result postcondition `Result (Result'First) =
'/'`). The deeper *functional* no-escape contract — proving the output is a fully
normalised absolute path with no `..`/`.`/`//` component, the path-traversal
guarantee the spec comments describe in full — is **deferred, not requested**
(decided 2026-06-28). The socket-driving `FTP_Server` body stays `SPARK_Mode Off`
and calls into `FTP_Paths`.

**Value: highest *security* relevance. Effort: came in as estimated (refactor + AoRTE).**

---

## Out of scope (recorded so it isn't re-triaged)

- **Tier B — register drivers.** The new `esp32s3-tlv2556` SPI ADC, plus the merged
  churn in `esp32s3-spi` / `*-engine`, `esp32s3-w25q`, `esp32s3-w5500*`,
  `esp32s3-sd_spi`. These belong to the existing Tier-B register-driver effort
  (SPARK subset + AoRTE with target-faithful representation), not this networking
  roadmap. Not "highest value" relative to the attacker-facing parsers above.
- **Tier C — `SPARK_Mode Off`.** The socket-coupled FTP control flow, the
  `gnat-sockets` facade additions, and `ext4-vfs` rely on controlled handles /
  `Ada.Finalization` and stay out of the subset by design.

---

## Recommended order

1. ✅ **`Net_Routes`** — AoRTE + the `Resolve` functional postcondition, done
   (54/54 VCs, 0 justified). Cleanest, smallest, and the only new unit with a
   realistic functional spec.
2. ✅ **FTP client PASV / reply parsers** — factored into `FTP_Replies` and proved
   (56/56 VCs, 0 justified); found & fixed a PASV integer-overflow bug.
3. ✅ **FTP server path resolution** — refactored into the pure `FTP_Paths` unit
   (`Abs_Path` / `Split`) and proved AoRTE **plus the functional no-escape
   postcondition** (`No_Parent_Ref (Result)`), 230/230 VCs, 0 justified. **All
   three net-roadmap targets are now proved — and the path-traversal guard goes
   beyond AoRTE to a functional security property.**
