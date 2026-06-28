# Roadmap — remaining SPARK proof / conversion targets

Tier A (the crypto / X.509 certificate-verification core) and the whole
post-merge **networking** triage are proved end-to-end. What landed:

- **Proved units** (AoRTE, several with functional contracts): `X509` / `X509.DER`,
  `Cert_Verify`, `Chain_Verify`, `AES.GCM`, `SPARKNaCl`, **`Net_Routes`** (+ `Resolve`
  functional postcondition), **`FTP_Replies`** (PASV/reply parse — found & fixed a real
  integer-overflow bug), **`FTP_Paths`** (path-traversal guard + functional no-escape
  postcondition), **`DNS_Parse`** (DNS A-record reply parser — closes the unbounded
  `Skip_Name` overrun and the A-record OOB read the inline `Resolve` carried),
  **`ESP32S3.GPS.NMEA`** (NMEA-0183 decoder — proved AoRTE in place; closes the
  unguarded accumulator overflows and a GSV message-number `* 4` overflow).
  Per-unit VC counts are in `README.md`; the reusable proof techniques
  are in `proof-patterns.md`; Tier-A phase tables and the bugs proof found are in
  `tier-a-results.md`.

This file now triages the *next* wave: code in the tree that is **not yet in SPARK**.
It is a *static* triage from reading the sources — no gnatprove run yet. Targets are
ordered by **value-per-effort** against the project's proof profile (attacker-facing,
heap-free, no controlled types / `Ada.Finalization`, no secondary stack,
target-portable). The mechanics (cross-target via `target.atp`, contract-only deps,
the in-buffer-predicate / workhorse-lemma patterns, the factor-the-pure-parser
refactor) are all in `proof-patterns.md` — reuse them.

---

## ▶ STATUS

| # | Target | Tier | Shape | Value | Effort |
|--:|--------|------|-------|-------|--------|
| ✅ | ~~`DNS_Client` reply parse~~ | A (AoRTE) | **done** — `DNS_Parse.Parse_Reply` factored out, proved 41/41 VCs; see §1 | — | — |
| 2 | DHCP reply option walk (`ESP32S3.W5500.DHCP.Parse_Reply`) | A (AoRTE) | factor pure parser out of the socket loop | high — attacker-facing TLV walk | small–medium |
| 3 | `NTP_Client` timestamp parse | A (AoRTE) | factor / annotate | medium | small |
| ✅ | ~~`ESP32S3.GPS.NMEA`~~ | A (AoRTE) | **done** — annotated in place, proved 223/223 VCs; see §4 | — | — |
| 5 | `Modbus` frame `Process` (slave/master PDUs) | A (AoRTE) | factor out of socket `Serve` | medium — bus-facing | medium |
| 6 | ext4 `crc32c` / `bitmap` / `mkfs`, `Block_Dev.WL` | A (AoRTE) | **already host-tested / pure** | medium (FS + flash integrity) | medium |
| 7 | `P256` (TLS ECDH field arithmetic) | A (AoRTE + functional) | SPARKNaCl-style proof project | high (TLS key exchange) | large |
| — | TLV2556 + SPI/`*-engine` / `w25q` / `w5500` / `sd_spi` register churn | B (register drivers) | folds into the Tier-B bucket | — | — |
| — | Socket-coupled FTP/DNS/Modbus control flow, `gnat-sockets`, `ext4-vfs` | C (`SPARK_Mode Off`) | out of subset — controlled handles | n/a | n/a |

---

## 1. `DNS_Client` reply parsing — ✅ DONE (`DNS_Parse`, 41/41 VCs)

**Resolved.** The inline parse was factored into a pure `DNS_Parse.Parse_Reply
(Resp, RLast; Host, Found)` over the `Stream_Element_Array` reply slice
(`dns_parse.{ads,adb}`, `SPARK_Mode On`), proved AoRTE at `--level=2`
(`proof/dns_parse_proof.gpr`, 41/41 VCs, 0 unproved/0 justified/0 warnings). The
socket-driving `DNS_Client.Resolve` stays `SPARK_Mode Off` and calls it. The proof
closed exactly the bugs the static read predicted:

- **`Skip_Name` is now provably bounded.** It is a fixed-trip-count `for` loop with a
  top `Pos > RLast` fail-closed guard and a `Pos <= RLast + 1` postcondition; a
  compression pointer ends the name (never followed), so there is no resolver
  pointer-loop and no unbounded `Pos` walk.
- **The A-record read can no longer index past the buffer.** The fixed RR header is
  guarded by `Pos + 9 > RLast` and the 4 RDATA bytes by a *separate* `RData + 3 >
  RLast` (the old single `Pos + 10 > RLast` guard was the OOB bug).
- **Short replies fail closed.** A `RLast < Resp'First + 11` header-length check
  gates every field read; truncated names/answers exit the walk with `Found = False`.

The remainder of this section is kept for the record (what the static read found).

`libs/esp32s3_hal/src/dns_client.{ads,adb}`, ~150 LOC. A textbook attacker-facing
parser, and a static read already turns up **concrete AoRTE bugs** — the same payoff
shape as the PASV overflow `FTP_Replies` caught:

- **`Skip_Name` (line 59) advances unbounded.** The loop reads `Resp (Pos)` and does
  `Pos := Pos + 1 + Len` with **no upper-bound check on `Pos`**. A hostile reply (a
  label run, or a label whose length overshoots) walks `Pos` past `Resp'Last` → an
  out-of-bounds read / `Constraint_Error`. (DNS compression pointers also invite a
  pointer *loop*, the classic resolver bug — worth a bounded-iteration invariant.)
- **The A-record read can index past the buffer.** The answer loop guards only
  `Pos + 10 > RLast` (line 101), but then reads `Resp (RData .. RData + 3)` with
  `RData = Pos + 10` (line 110). With `Pos = RLast - 10` and `RLast` near the end,
  `RData + 3` reaches `Resp'Last + 3 (= 514 > 511)` → **out-of-bounds read**.
- **Header fields read before length is checked.** `U16 (Resp'First + 6)` (answer
  count, line 94) and the subsequent `Skip_Name`/`+4` walk read bytes that a short
  reply never delivered — uninitialised-data / bounds flow issues.

**Refactor (the established pattern).** The parse is currently inline in `Resolve`,
interleaved with `GNAT.Sockets` I/O (Tier C). Factor a pure
`Parse_Reply (Resp, RLast; Addr : out Inet_Addr_Type; Ok : out Boolean)` — or a
small `DNS_Parse` package over a `Stream_Element_Array` slice + length — mark it
`SPARK_Mode On`, and prove AoRTE: every `Resp (..)` index in range, `Skip_Name`
bounded and loop-free, `RData + 3 <= RLast`, fail-closed on a truncated reply. The
socket-driving `Resolve` stays `SPARK_Mode Off` and calls it.

**Value: highest — real attacker surface (the resolver answer steers every later
connection) and the proof will almost certainly surface live bugs. Effort: small
once factored; the buffer shape matches `FTP_Replies`.**

---

## 2. DHCP reply option parsing — attacker-facing TLV walk

`libs/esp32s3_hal/src/esp32s3-w5500-dhcp.adb`, `Parse_Reply`. The option scan
(`Len := Natural (RX (P + 1))`, then `RX (P + 2 + I)` for the 4-byte address
options 1/3/6/54, then `P := P + 2 + Len`) is driven by **server-supplied lengths**.
The `while P <= Count - 1` guard bounds `P` but **not** the inner reads `RX (P + 2 + I)`
(reach `P + 5`) against the received length / `RX'Last` — a crafted option near the
end of the datagram reads past the data. Same factor-the-pure-parser refactor: lift
the option walk into a `SPARK_Mode On` helper taking the `RX` slice + `Count`, prove
every index in range and the advance monotone (so the outer loop terminates), leave
the socket `Do_Acquire` / `Renew` flow `SPARK_Mode Off`.

**Value: high (a rogue DHCP server controls gateway/DNS/subnet the device adopts).
Effort: small–medium.**

---

## 3. `NTP_Client` — server timestamp parse

`libs/esp32s3_hal/src/ntp_client.{ads,adb}`, ~120 LOC total. Small. Parses a
server-supplied 64-bit NTP timestamp out of a fixed-offset packet and converts to a
`Time`/`Duration`. Factor the fixed-offset field extraction + the seconds/fraction
arithmetic (watch the `* 1000` / epoch-offset conversions for overflow) into a pure
helper and prove AoRTE. Low effort; modest but real attacker surface (clock skew).

---

## 4. `ESP32S3.GPS.NMEA` — ✅ DONE (annotated in place, 223/223 VCs)

**Resolved.** `esp32s3-gps-nmea.{ads,adb}` were marked `SPARK_Mode On` in place — no
refactor, exactly as the static read predicted — and proved AoRTE at `--level=2`
(`proof/nmea_proof.gpr`, 223/223 VCs, 0 unproved/0 justified/0 warnings). The proof
project pulls in only the `ESP32S3.GPS` *spec* (and its with-closure of specs) so
the prover can see the parent data types; the task/protected-store `ESP32S3.GPS`
body that drives the decoder stays `SPARK_Mode Off` and consumes it by call. The
proof closed exactly the AoRTE holes the static read flagged, plus one the read
missed:

- **The decimal accumulators are now overflow-safe.** `To_Nat` and `Frac`
  (`Acc := Acc * 10 + digit`) gained the `FTP_Replies` cap idiom — an
  `exit when Acc > Digit_Cap` guard with a flat loop invariant — so a hostile,
  arbitrarily long digit run saturates at < 1e9 instead of overflowing `Natural`.
- **`Scaled` / `Coord` compute in `Long_Long_Integer` and clamp.** The `*10**Places`
  scaling and the `ddmm.mmmmm → 1e-7°` coordinate maths now run in `LLI` and clamp
  to `Integer'Last` / `Integer_32`'range, so an oversized field can neither overflow
  the intermediate nor raise on the narrowing conversion (the old direct
  `Integer_32 (Deg_E7)` was an unguarded `Constraint_Error`).
- **A GSV message-number overflow the static read missed.** `Before := 4 * (Msg_No - 1)`
  multiplied a *server-supplied* message number by 4 with no bound — a crafted GSV
  overflows `Natural` before the in-view comparison. Now the product is taken only
  when `Msg_No - 1 <= In_V / 4`; past that the message is beyond the in-view set and
  `Here` collapses to 0.
- **Index walks proved in range.** `Field`'s comma scan, `Check`'s `*HH` walk (its
  `Star + 2 > 'Last` guard rewritten as `Star > 'Last - 2` so the guard itself can't
  overflow), and the GGA/RMC/GSV field reads all discharge their index-in-range and
  `'First + k` obligations under a single realistic-window precondition
  (`Sentence'Last <= Integer'Last - 1`, true for every real String).

---

## 5. `Modbus` frame processing — bus-facing PDU handling

`libs/esp32s3_hal/src/modbus*.{ads,adb}`. The request/response **PDU builders and
parsers** (`Modbus.Slave.Process`, the `Get_U16` / `Put_U16` helpers, the
quantity-driven `Buf (9 + 2*I)` register loops) index a frame buffer by a
**client-supplied quantity / byte-count** — classic index-overflow surface on an
industrial bus. Already **host-tested** (`test/modbus*`), so the logic is
hardware-decoupled. Factor the PDU encode/decode away from the socket `Serve` /
`Recv_Exact` loop (Tier C) and prove AoRTE: every `Buf` index bounded by the declared
quantity, quantities clamped to the Modbus limits (≤ 125 registers / ≤ 2000 coils).

**Value: medium (bus-facing, safety-adjacent). Effort: medium.**

---

## 6. ext4 integrity primitives + wear levelling

`libs/esp32s3_hal/src/ext4/`. Several units are pure block/index arithmetic and
**already host-tested** (`test/ext4_host`, `test/mkfs_host`, `test/wl_host`):
- `ESP32S3.Ext4.CRC32C` — table/loop checksum, pure, trivially in subset.
- `ESP32S3.Ext4.Bitmap` — block/inode bitmap bit math (alloc/free), index-heavy.
- `ESP32S3.Ext4.MkFs` — superblock / group-descriptor layout arithmetic.
- `ESP32S3.Block_Dev.WL` — wear-levelling sector remap (logical→physical index math).

These are **integrity**, not attacker-facing, targets: AoRTE on the index/offset
arithmetic (no out-of-range block, no overflow in the remap), with `CRC32C` the
cleanest first step. The `Ext4.FS` / `Ext4.File` / `ext4-vfs` layers depend on
controlled handles and stay Tier C.

**Value: medium (filesystem + flash integrity). Effort: medium, incremental
unit-by-unit.**

---

## 7. `P256` — TLS ECDH field arithmetic

`libs/tls/src/p256.{ads,adb}`, ~630 LOC. P-256 scalar multiplication over big-endian
`Bytes`, the secp256r1 field arithmetic behind the TLS key exchange. This is a real
**proof project**, the natural successor to the SPARKNaCl GF(2²⁵⁵-19) replay: the
same carry-chain / limb-range invariant style, AoRTE plus (ideally) the functional
"output is the reduced field element" postcondition. High value — it is the live key
exchange in `TLS_Client` — but heavy; schedule it as its own effort, not a quick AoRTE
pass.

---

## Out of scope (recorded so it isn't re-triaged)

- **Tier B — register drivers.** `esp32s3-tlv2556` and the SPI / `*-engine` /
  `w25q` / `w5500*` / `sd_spi` register churn. These belong to the standing Tier-B
  register-driver effort (SPARK subset + AoRTE with target-faithful representation),
  not this roadmap.
- **Tier C — `SPARK_Mode Off`.** Socket-coupled control flow (FTP/DNS/NTP/Modbus
  `Resolve` / `Serve` / session layers), the `gnat-sockets` facade, and `ext4-vfs`
  rely on controlled handles / `Ada.Finalization` and stay out of the subset by
  design. Each proof target above keeps its socket/VFS driver here and exposes a
  pure, proved parser/primitive to it.

---

## Recommended order

1. ~~**`DNS_Client`**~~ — ✅ done (`DNS_Parse`, 41/41 VCs); see §1.
2. ~~**`NMEA`**~~ — ✅ done (annotated in place, 223/223 VCs); see §4.
3. **DHCP** then **NTP** — finish the attacker-facing network-parser sweep.
   **Start here next** (§2 — the DHCP reply option walk).
4. **Modbus PDU** / **ext4 `CRC32C` + bitmap + WL** — integrity targets, incremental.
5. **`P256`** — schedule as a dedicated crypto-proof project.
