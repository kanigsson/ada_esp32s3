# esp32s3_full_tasking — full-Ada-tasking demo (`ESP32S3_RTS_PROFILE=full`)

Runs on the **full** runtime profile (`crates/esp32s3_rts/full_overlay`),
which carries the complete GNARL tasking kernel on the bare-metal ESP32-S3 — no
Jorvik restrictions. Everything is scheduled over the BB kernel
(`s-tassta`/`s-tasren` → the hand-written `s-taprop` → `s-bbthre`).

This example **dynamically allocates** two task objects (`new Worker` — a *task
allocator*, forbidden by Jorvik); the enclosing block is their **master** and
**waits for them to terminate** (task hierarchy + termination) before freeing
their ATCBs. Each task's primary stack comes from the **Ada heap** — which lives
in **internal DRAM** by default in this example, but can be moved to external
PSRAM with one build knob (see below).

Other full-tasking constructs verified on this hardware (also forbidden under
Jorvik): **rendezvous** (task entries / `accept` / entry calls with `out`
parameters), **nested tasks** (a task declared in a subprogram, with the
subprogram blocking on return until it terminates), **protected-object entries**
(blocking on a barrier, woken by another task's protected action),
**`Ada.Task_Attributes`** and **`Ada.Dynamic_Priorities`**.

```
./x run full_tasking      # build + flash + monitor (IDF-free bare boot)
```

Expected (heap in DRAM, the default — so no `stack is in PSRAM` line; build
with `HEAP_PSRAM=1` and the workers will print it, see below):

```
[C] Ada runtime up on both cores
=== full Ada tasking: dynamic tasks (M4) + abort (M5) ===
    [heartbeat] beat
    [worker 1 ] 1
    [worker 2 ] 1
[main] 2 dynamic tasks allocated; block awaits them
    [worker 1 ] 2 / [worker 2 ] 2 / ... / [worker 1 ] terminating
[main] block exited -> both dynamic tasks terminated + freed
[main] Heartbeat'Terminated before abort = FALSE
[main] Heartbeat'Terminated after  abort = TRUE
[main] done.
```

## Where task stacks and the heap live (internal RAM vs PSRAM)

The full runtime allocates each **task's primary stack** through
`Alloc_Task_Stack` (`s-taprop.adb`). That routine first checks a weak BSP hook,
`__gnat_task_stack_alloc(size)`; if the application does **not** define it (the
symbol resolves to null), stacks fall back to the **Ada heap** via
`System.Memory.Alloc` (roughly C `malloc` → the bare-boot TLSF allocator,
`examples/common/bare/boot/bare_heap.adb`). Ada `new` allocations use that same
Ada heap.

**This example does not define `__gnat_task_stack_alloc`** — there is no
`glue.c` in this directory at all. So both `new` objects **and** every task
stack come from the one Ada heap. Where that heap lives is therefore the single
knob that decides whether task stacks are in internal RAM or PSRAM.

The heap's bounds are **not** defsyms in a `CMakeLists.txt`; they are
`--defsym`'d by the shared bare-boot build (`examples/common/bare/bare_build.sh`)
as `__bare_heap_base`/`__bare_heap_end`, driven by env vars this example's
`build.sh` sets (and which any caller can override):

- `HEAP_SIZE=196608` — request a heap (the exception-capable full profile needs
  one; each `new Worker` task also takes a `-D16k` 16 KB stack out of it).
- `ENV_STACK_SIZE=65536` — the environment-task primary stack (a DRAM
  `ada_env_stack` array; the env and idle/kernel stacks always stay in internal
  RAM).
- `HEAP_PSRAM` is **unset**, so the heap arena is the leftover internal **DRAM**
  (`__bare_heap_base = _heap_low_start`, `__bare_heap_end = _bare_heap_top`;
  ~0x3FCC_5000..0x3FCF_0000 in `app.map`). Task stacks land here, in internal
  RAM.

To move the heap — and with it every `new` allocation **and** every task
stack — into the bootloader-mapped external PSRAM, set one env var in
`build.sh` (this requires `PSRAM_Size > 0` in `board.ads`; here it is 2 MB):

```
export HEAP_SIZE=196608 ENV_STACK_SIZE=65536 HEAP_PSRAM=1
```

`bare_build.sh` then points `__bare_heap_base`/`__bare_heap_end` at the PSRAM
window (base `0x3D00_0000`, `BOARD_PSRAM_SIZE` bytes). The whole Ada heap, and
thus the worker task stacks, then live in PSRAM — and the demo's `In_PSRAM`
check goes true, printing `stack is in PSRAM`. There is no separate
"stacks-only-in-PSRAM" mode in this example: with no `__gnat_task_stack_alloc`
hook, stacks follow the heap. (A BSP that wanted stacks in PSRAM while keeping
`new` in DRAM could define `__gnat_task_stack_alloc` in a `glue.c` to allocate
from a PSRAM region directly; this example does not.)

| Heap (and therefore stacks) | `build.sh` knob | Where it lands |
|---|---|---|
| Internal DRAM (**default here**) | `HEAP_PSRAM` unset | `_heap_low_start.._bare_heap_top` (DRAM) |
| External PSRAM | `HEAP_PSRAM=1` | `0x3D00_0000`, `BOARD_PSRAM_SIZE` bytes |

### The trade-off (PSRAM heap)

A flash erase/program **disables the SPI cache**, during which PSRAM (and
flash-XIP) is inaccessible — a task running on a PSRAM stack at that moment
would fault (`Cache disabled but cached memory region accessed`). This runtime
**never writes flash at run time**, so it is safe. If you later add flash
writes (NVS/OTA), perform them from an internal-RAM-stacked task with the
PSRAM-using tasks suspended. The interrupt/kernel path and the **environment and
idle task stacks always stay in internal RAM** regardless of this setting.

> Abort: **`abort` works** for a task that reaches an abort-completion point
> (the `Heartbeat` `delay` loop above — `'Terminated` goes `False → True`). It
> was enabled by forcing `System.Parameters.No_Abort = False` (the bareboard
> inherited `True` from Ravenscar, which compiled the abort machinery out). Not
> yet: a task parked on a **protected entry** or in a pure **CPU loop**, and
> `select … then abort` (ATC), do not abort yet (they stay put — no crash); the
> remaining kernel pieces are in
> `crates/esp32s3_rts/full_overlay/README.md`. `Ada.Dynamic_Priorities`
> `Set_Priority` works when it keeps the task at or above its ready peers;
> *lowering* the running task below its peers hits a BB-kernel reschedule edge
> case. Terminated tasks are parked and their ATCBs reclaimed only for `new`
> task objects (declared-task ATCBs live in their frame); per-task stacks are
> not yet returned to the heap on termination.
