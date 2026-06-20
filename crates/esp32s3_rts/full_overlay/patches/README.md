# `full_overlay/patches/` — full-profile runtime source patches

Unified-diff patches that `gen_runtime.sh` applies to the **`full`** runtime's
generated GNARL/GNAT source after it synthesizes `full` (clone `embedded` + overlay
`full_overlay/`, import the donor full-tasking units). Each is a fix this ESP32-S3
port needs on top of the stock AdaCore sources.

These exist so the patches are **plain `diff`/`patch`** (a tool in every Linux
distro) instead of inline Python in `gen_runtime.sh`. They have nothing to do with
`build_rts.py` (the upstream bb-runtimes generator) — they patch its *output*.

## The patches

| File | Patches | Fix |
|---|---|---|
| `01-s-secsta-heap-secondary-stacks.patch` | `gnat/s-secsta.{ads,adb}` | Heap-manage task secondary stacks (`SS_Free` reclaims on termination; built `-Q0`), so a long-lived program creating many tasks doesn't exhaust the monotonic binder pool → `STORAGE_ERROR`. |
| `02-s-taskin-trampoline-iram-alias.patch` | `gnarl/s-taskin.adb` | Re-point a stack/DRAM nested-function GCC trampoline (`Task_Entry_Point`) at its SRAM1 **IRAM alias** (`+0x6F_0000`) so the indirect `callx` is fetchable (else `InstructionFetchError`). |
| `03-a-reatim-to-time-span.patch` | `gnarl/a-reatim.adb` | `To_Time_Span` of a **nonzero** `Duration` must not underflow to a zero `Time_Span` (the 4.17 ns tick is coarser than `Duration'Small`); round to ≥1 tick. Fixes the ACATS CXD8002 scale-up loop. |
| `04-a-dynpri-reapply-priority.patch` | `gnarl/a-dynpri.adb` | Re-apply a task's own `Set_Priority` **after** the ATCB unlock (this port's `Unlock` restores the lock-time priority, clobbering the change). ACATS CXD4009. |
| `05-priority-d23-fifo.patch` | `gnarl/s-bbthre.{ads,adb}`, `s-osinte.ads`, `s-taprop.adb` | RM **D.2.3** `FIFO_Within_Priorities`: a base-priority set moves the task to the **tail** of its ready queue (`Yield`), and a cross-task inheritance **raise** boosts the acceptor before waking it. ACATS CXD2001 / CXD2003 / CXD4005. |

(Simpler one-line edits — `s-interr`, `s-parame`, the `a-reatim` Clock fix,
`s-taenca`, `s-tasren`, `s-tpobop` — stay as `sed` in `gen_runtime.sh`; only the
multi-line structural inserts are patches.)

## How they're applied

`gen_runtime.sh`, in the `PROFILE = full` branch:

```sh
patch -p1 -d "$RTS" < "$HERE/full_overlay/patches/NN-name.patch"
```

- `-p1` strips the leading `a/` `b/` of the diff paths.
- Applied **once** per fresh generation (the whole block is guarded by the runtime
  dir being absent), so idempotency isn't needed.
- Order matters only where a patch follows a `sed` on the same file: `03` applies
  to the **post-Clock-sed** `a-reatim.adb`.
- Only the `full` profile is patched; `embedded` / `light-tasking` use the plain
  `build_rts.py` output.

## Adding or regenerating a patch

1. Instrument `gen_runtime.sh` to `cp "$RTS/<path>" /tmp/before/` just before your
   edit and to `/tmp/after/` just after.
2. Regenerate `full` (`rm -rf full-esp32s3 && ESP32S3_RTS_PROFILE=full bash gen_runtime.sh`).
3. `diff -u before/<path> after/<path>` → the `.patch` (use `a/<rel>` `b/<rel>`
   paths so `patch -p1 -d "$RTS"` resolves).
4. Replace the temporary edit with a `patch -p1 -d "$RTS" < ...` call.

Verify a clean `full` regen applies every hunk with no failures and the runtime
builds (`adalib/libgnat.a`, `libgnarl.a`).
