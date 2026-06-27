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
| 2 | FTP client reply parsers (`ftp_client.adb` pure helpers) | A-profile (AoRTE) | ⬜ not started — needs a factoring refactor — **start here** |
| 3 | FTP server path resolution (`Abs_Path` / `Resolve_Path`) | A-profile (AoRTE) | ⬜ not started — needs a bounded-buffer refactor |
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

## 2. FTP client reply parsers — the attacker-facing parse

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

## 3. FTP server path resolution — highest security relevance, higher effort

`libs/esp32s3_hal/src/ftp_server.adb`. `Abs_Path` and `Resolve_Path` decide whether
a client-supplied path escapes its mount — i.e. **path-traversal on the board's
flash** (`/flash/../../...`). That is the scariest attacker surface in the new code.

But these helpers `return String` (secondary stack) and are coupled to the VFS, so
proving them requires a **bounded fixed-buffer refactor** first (return into a
caller-supplied `String` + `Last`, the same move that took `Parse_Time` into the
subset in Tier A). Worth doing eventually for the traversal guarantee; not a cheap
win, so it trails #1 and #2.

**Value: highest *security* relevance. Effort: medium (refactor-gated).**

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
2. **FTP client PASV / reply parsers** — factor `Parse_Pasv` out and prove the
   attacker-facing parse. ← **next**
3. **FTP server path resolution** — bounded-buffer refactor, then prove no
   mount escape.
